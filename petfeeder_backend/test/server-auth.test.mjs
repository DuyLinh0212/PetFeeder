import assert from 'node:assert/strict';
import {once} from 'node:events';
import test from 'node:test';
import {WebSocket} from 'ws';
import {MemoryStorage} from './helpers/memoryStorage.mjs';

test('Render requires a token and protects both HTTP commands and realtime snapshots', async t => {
  process.env.RENDER = 'true';
  process.env.HOST = '127.0.0.1';
  process.env.PORT = '0';
  delete process.env.PETFEEDER_API_TOKEN;
  const {startServer} = await import('../src/server.js');
  await assert.rejects(startServer(), /PETFEEDER_API_TOKEN is required/);

  const token = 'render-test-secret+/=';
  process.env.PETFEEDER_API_TOKEN = token;
  const {server, realtime, integration} = await startServer({
    legacyFile: null,
    storage: new MemoryStorage(),
    transport: {mode: 'TEST', send: async () => true},
  });
  t.after(async () => {
    for (const peer of realtime.clients) peer.terminate();
    realtime.close();
    await new Promise(resolve => server.close(resolve));
    await integration.close();
  });
  const address = `127.0.0.1:${server.address().port}`;
  const request = (path, options) => fetch(`http://${address}${path}`, options);
  const status = headers => request('/api/device/status', {headers});

  assert.equal((await request('/health')).status, 200);
  assert.equal((await request('/api/feeding/feed', {method: 'POST'})).status, 401);
  assert.equal((await status({Authorization: 'Bearer wrong'})).status, 401);
  assert.equal((await status({Authorization: `Bearer ${token}`})).status, 200);

  const realtimeUrl = `ws://${address}/api/realtime`;
  await assert.rejects(once(new WebSocket(realtimeUrl), 'open'), /401/);
  const socket = new WebSocket(realtimeUrl, [
    'petfeeder',
    `petfeeder.token.${Buffer.from(token).toString('base64url')}`,
  ]);
  const [snapshot] = await once(socket, 'message');
  assert.equal(socket.protocol, 'petfeeder');
  assert.equal(JSON.parse(snapshot).type, 'snapshot');
});
