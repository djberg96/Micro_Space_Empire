const {spawn} = require('node:child_process');
const http = require('node:http');
const net = require('node:net');

async function availablePort() {
  return new Promise((resolve, reject) => {
    const listener = net.createServer();
    listener.once('error', reject);
    listener.listen(0, '127.0.0.1', () => {
      const {port} = listener.address();
      listener.close((error) => error ? reject(error) : resolve(port));
    });
  });
}

function checkReady(url) {
  return new Promise((resolve) => {
    const request = http.get(url, (response) => {
      response.resume();
      resolve(response.statusCode === 200);
    });
    request.setTimeout(500, () => request.destroy());
    request.once('error', () => resolve(false));
  });
}

async function startServer(binary, database, libraries, timeoutMs = 10000) {
  const port = await availablePort();
  const url = `http://127.0.0.1:${port}/`;
  const child = spawn(binary, [], {
    env: {
      ...process.env,
      KEMAL_ENV: 'production',
      MSE_HOST: '127.0.0.1',
      MSE_PORT: String(port),
      MSE_DATABASE_PATH: database,
      MSE_OPEN_BROWSER: 'false',
      LD_LIBRARY_PATH: [libraries, process.env.LD_LIBRARY_PATH].filter(Boolean).join(':')
    },
    stdio: ['ignore', 'ignore', 'pipe']
  });

  let failure = '';
  let spawnError;
  child.stderr.setEncoding('utf8');
  child.stderr.on('data', (chunk) => {
    failure = (failure + chunk).slice(-3000);
  });
  child.once('error', (error) => { spawnError = error; });

  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline && child.exitCode === null && child.signalCode === null && !spawnError) {
    if (await checkReady(url)) return {child, url};
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  if (child.exitCode === null && child.signalCode === null) child.kill('SIGTERM');
  throw new Error(`Game server did not start: ${spawnError?.message || failure.trim() || `timed out or exited (${child.exitCode ?? child.signalCode})`}`);
}

module.exports = {startServer};
