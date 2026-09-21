root = File.expand_path("..", __DIR__)
paths = Dir.glob(File.join(root, "{data/*.json,public/**/*}"))
  .select { |path| File.file?(path) }
  .sort

paths.each do |path|
  relative = Path[path].relative_to(Path[root]).to_s.gsub('\\', '/')
  puts %(files[#{relative.inspect}] = {{ read_file(#{path.inspect}) }})
end
