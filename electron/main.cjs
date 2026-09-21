const {app, BrowserWindow, dialog, shell} = require('electron');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {startServer} = require('./server.cjs');

let gameServer;
let quitting = false;

function serverBinary() {
  return app.isPackaged
    ? path.join(process.resourcesPath, 'micro-space-empire-server')
    : path.resolve(__dirname, '..', 'dist', 'micro-space-empire-electron-server');
}

function serverLibraries() {
  return app.isPackaged
    ? path.join(process.resourcesPath, 'server-libs')
    : path.resolve(__dirname, '..', 'dist', 'micro-space-empire-electron-libs');
}

function savePath() {
  const dataHome = process.env.XDG_DATA_HOME || path.join(os.homedir(), '.local', 'share');
  const directory = path.join(dataHome, 'micro-space-empire');
  fs.mkdirSync(directory, {recursive: true, mode: 0o700});
  return path.join(directory, 'micro_space_empire.db');
}

async function createWindow() {
  const binary = serverBinary();
  if (!fs.existsSync(binary)) throw new Error(`Missing ${binary}. Run make electron-server first.`);

  gameServer = await startServer(binary, savePath(), serverLibraries());
  const origin = new URL(gameServer.url).origin;
  const window = new BrowserWindow({
    title: 'Micro Space Empire',
    width: 1440,
    height: 900,
    minWidth: 1000,
    minHeight: 700,
    backgroundColor: '#071018',
    show: false,
    autoHideMenuBar: true,
    webPreferences: {nodeIntegration: false, contextIsolation: true, sandbox: true}
  });

  window.webContents.on('will-navigate', (event, url) => {
    try {
      if (new URL(url).origin === origin) return;
    } catch (_) {}
    event.preventDefault();
  });
  window.webContents.setWindowOpenHandler(({url}) => {
    // Never load arbitrary sites with application privileges.
    if (/^https?:\/\//i.test(url) && new URL(url).origin !== origin) shell.openExternal(url);
    return {action: 'deny'};
  });
  window.once('ready-to-show', () => window.show());
  window.webContents.once('did-fail-load', (_, code, description) => {
    dialog.showErrorBox('Micro Space Empire', `Could not load the game (${code}): ${description}`);
  });
  gameServer.child.once('exit', () => {
    if (!quitting && !window.isDestroyed()) {
      dialog.showErrorBox('Micro Space Empire', 'The local game server stopped unexpectedly.');
      window.close();
    }
  });
  await window.loadURL(gameServer.url);
}

app.on('window-all-closed', () => app.quit());
app.on('before-quit', () => {
  quitting = true;
  gameServer?.child.kill('SIGTERM');
});

app.whenReady().then(createWindow).catch((error) => {
  dialog.showErrorBox('Micro Space Empire could not start', error.message);
  app.quit();
});
