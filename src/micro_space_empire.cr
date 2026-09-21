require "kemal"
require "uri"
require "./micro_space_empire/content"
require "./micro_space_empire/models"
require "./micro_space_empire/rng"
require "./micro_space_empire/engine"
require "./micro_space_empire/store"
require "./micro_space_empire/renderer"

ROOT     = ENV.fetch("MSE_ROOT", Dir.current)
CONTENT  = MicroSpaceEmpire::Content.load(ROOT)
CONTENT.validate!(ROOT)
ENGINE = MicroSpaceEmpire::GameEngine.new(CONTENT)
STORE = MicroSpaceEmpire::Store.open(ROOT)
RENDERER = MicroSpaceEmpire::Renderer.new(CONTENT, ENGINE)

private def open_browser? : Bool
  value = ENV["MSE_OPEN_BROWSER"]?
  return false unless value
  !{"0", "false", "no", "off"}.includes?(value.downcase)
end

private def game_url(config : Kemal::Config) : String
  host = config.host_binding
  host = "127.0.0.1" if {"0.0.0.0", "::"}.includes?(host)
  host = "[#{host}]" if host.includes?(':') && !host.starts_with?('[')
  "#{config.scheme}://#{host}:#{config.port}/"
end

private def open_game_in_browser(url : String) : Nil
  status = Process.run("/usr/bin/open", [url], output: Process::Redirect::Close, error: Process::Redirect::Close)
  Kemal::Log.warn { "Could not open the browser. Visit #{url}" } unless status.success?
rescue ex
  Kemal::Log.warn { "Could not open the browser. Visit #{url} (#{ex.message})" }
end

Kemal.config.host_binding = ENV.fetch("MSE_HOST", "127.0.0.1")
Kemal.config.port = ENV.fetch("MSE_PORT", "3000").to_i
serve_static false

before_all do |env|
  method = env.request.method
  if method != "GET" && method != "HEAD"
    if origin = env.request.headers["Origin"]?
      uri = URI.parse(origin)
      host = env.request.headers["Host"]?
      unless host && uri.authority == host
        halt env, status_code: 403, response: "Cross-origin requests are not allowed."
      end
    end
  end
end

get "/assets/*path" do |env|
  relative_path = File.join("public", "assets", env.params.url["path"])
  unless MicroSpaceEmpire::EmbeddedFiles.has_key?(relative_path)
    halt env, status_code: 404, response: "Asset not found."
  end

  env.response.content_type = case File.extname(relative_path)
                              when ".css"  then "text/css; charset=utf-8"
                              when ".js"   then "text/javascript; charset=utf-8"
                              when ".webp" then "image/webp"
                              else              "application/octet-stream"
                              end
  env.response.headers["Cache-Control"] = "no-cache"
  disk_path = File.join(ROOT, relative_path)
  File.exists?(disk_path) ? File.read(disk_path) : MicroSpaceEmpire::EmbeddedFiles.fetch(relative_path)
end

get "/" do |env|
  env.response.content_type = "text/html; charset=utf-8"
  RENDERER.menu(STORE.list)
end

get "/rules" do |env|
  env.response.content_type = "text/html; charset=utf-8"
  RENDERER.rules
end

post "/games" do |env|
  expansion = env.params.body["expansion"]? == "true"
  begin
    record = STORE.create_unsaved(ENGINE.new_game(expansion))
    env.redirect "/games/#{record.id}", status_code: 303
  rescue ex : Exception
    env.response.status_code = 422
    env.response.content_type = "text/html; charset=utf-8"
    RENDERER.menu(STORE.list, ex.message || "Could not create the save.")
  end
end

post "/games/:id/save" do |env|
  begin
    id = env.params.url["id"].to_i64
    STORE.save(id, env.params.body["name"]? || "")
    destination = env.params.body["destination"]? == "home" ? "/" : "/games/#{id}"
    env.redirect destination, status_code: 303
  rescue ex : Exception
    env.response.status_code = 422
    env.response.content_type = "text/html; charset=utf-8"
    id = env.params.url["id"].to_i64
    RENDERER.game(STORE.get(id), ex.message)
  end
end

post "/games/:id/discard" do |env|
  STORE.delete(env.params.url["id"].to_i64)
  env.redirect "/", status_code: 303
end

post "/games/:id/start-new" do |env|
  id = env.params.url["id"].to_i64
  begin
    current = STORE.get(id)
    expansion = env.params.body["expansion"]? == "true"
    preserve = env.params.body["preserve"]? || ""
    save_name = nil.as(String?)
    unless current.saved
      case preserve
      when "save"
        save_name = env.params.body["name"]? || ""
      when "discard"
      else
        raise MicroSpaceEmpire::StoreError.new("Choose whether to save the current game first.")
      end
    end
    next_game = STORE.start_new(id, ENGINE.new_game(expansion), save_name)
    env.redirect "/games/#{next_game.id}", status_code: 303
  rescue ex : Exception
    env.response.status_code = 422
    env.response.content_type = "text/html; charset=utf-8"
    RENDERER.game(STORE.get(id), ex.message || "Could not start a new game.")
  end
end

get "/games/:id" do |env|
  begin
    id = env.params.url["id"].to_i64
    env.response.content_type = "text/html; charset=utf-8"
    RENDERER.game(STORE.get(id))
  rescue ex : Exception
    env.response.status_code = 404
    env.response.content_type = "text/html; charset=utf-8"
    RENDERER.menu(STORE.list, ex.message || "Save not found.")
  end
end

post "/games/:id/actions" do |env|
  ajax = env.request.headers["X-Requested-With"]? == "fetch"
  begin
    id = env.params.url["id"].to_i64
    expected_version = env.params.body["expected_version"].to_i
    action = env.params.body["action"]
    target = env.params.body["target"]?
    choice = env.params.body["choice"]?
    record = STORE.get(id)
    raise MicroSpaceEmpire::StaleSaveError.new("This save changed in another tab. Reload before continuing.") unless record.version == expected_version
    ENGINE.apply(record.state, action, target, choice)
    record = STORE.update(id, expected_version, record.state)
    if ajax
      env.response.content_type = "application/json"
      {html: RENDERER.game_shell(record), transition: record.state.last_transition}.to_json
    else
      env.redirect "/games/#{id}", status_code: 303
    end
  rescue ex : Exception
    env.response.status_code = 422
    id = env.params.url["id"].to_i64?
    record = id ? STORE.get(id) : nil
    if ajax && record
      env.response.content_type = "application/json"
      {html: RENDERER.game_shell(record, ex.message || "The action could not be completed."), error: ex.message}.to_json
    else
      env.response.content_type = "text/html; charset=utf-8"
      record ? RENDERER.game(record, ex.message) : RENDERER.menu(STORE.list, ex.message)
    end
  end
end

post "/games/:id/rename" do |env|
  id = env.params.url["id"].to_i64
  STORE.rename(id, env.params.body["name"]? || "")
  env.redirect "/games/#{id}", status_code: 303
end

post "/games/:id/delete" do |env|
  STORE.delete(env.params.url["id"].to_i64)
  env.redirect "/", status_code: 303
end

error 404 do |env|
  env.response.content_type = "text/html; charset=utf-8"
  RENDERER.menu(STORE.list, "That page does not exist.")
end

at_exit { STORE.close }
Kemal.run do |config|
  if open_browser?
    url = game_url(config)
    spawn do
      sleep 250.milliseconds
      open_game_in_browser(url)
    end
  end
end
