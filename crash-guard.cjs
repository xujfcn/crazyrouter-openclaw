/**
 * Crazyrouter OpenClaw crash guard — 自托管版
 * 通过 --require 预加载，防止 undici 7.x + Node 22 TLS 崩溃。
 *
 * 补丁:
 *   1. TLSSocket.setSession null handle 保护
 *   2. tls.connect session 剥离（防止重用）
 *   3. uncaughtException 安全网（undici 瞬态错误）
 *   4. 过期 session lock 清理
 *   5. Memory 目录备份/恢复
 */
'use strict';

const os = require('os');
const tls = require('tls');
const fs = require('fs');
const path = require('path');

process.stderr.write('[crash-guard] 加载中 (Crazyrouter 自托管版)...\n');

// --- 补丁 1: TLSSocket.setSession — 保护 null _handle ---
const origSetSession = tls.TLSSocket.prototype.setSession;
if (origSetSession) {
  tls.TLSSocket.prototype.setSession = function (session) {
    if (session == null || !this._handle) return;
    return origSetSession.call(this, session);
  };
}

// --- 补丁 2: tls.connect — 剥离 session 选项 ---
const origConnect = tls.connect;
tls.connect = function (...args) {
  if (args[0] && typeof args[0] === 'object' && args[0].session) {
    delete args[0].session;
  }
  return origConnect.apply(tls, args);
};

// --- 补丁 3: uncaughtException 安全网 ---
let suppressCount = 0;
process.on('uncaughtException', (err) => {
  const msg = err?.message || '';
  const stack = err?.stack || '';
  const isUndiciTransient =
    (msg.includes("reading 'setSession'") || msg.includes('fetch failed')) &&
    stack.includes('undici');
  if (isUndiciTransient) {
    suppressCount++;
    process.stderr.write(`[crash-guard] 已抑制 undici 错误 #${suppressCount}: ${msg}\n`);
    return;
  }
  throw err;
});

// --- 补丁 4: 过期 session lock 清理 ---
const HOME_DIR = os.homedir();
const AGENTS_DIR = path.join(HOME_DIR, '.openclaw', 'agents');
const LOCK_MAX_AGE_MS = 11 * 60 * 1000;
const LOCK_SCAN_INTERVAL_MS = 30 * 1000;

function findLockFiles(dir) {
  const locks = [];
  try {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) locks.push(...findLockFiles(full));
      else if (entry.name.endsWith('.lock')) locks.push(full);
    }
  } catch { /* 目录可能尚不存在 */ }
  return locks;
}

function cleanStaleLocks(maxAge) {
  const now = Date.now();
  let cleaned = 0;
  for (const lockFile of findLockFiles(AGENTS_DIR)) {
    try {
      const stat = fs.statSync(lockFile);
      if (maxAge === 0 || now - stat.mtimeMs > maxAge) {
        fs.unlinkSync(lockFile);
        cleaned++;
      }
    } catch { /* 忽略 */ }
  }
  return cleaned;
}

cleanStaleLocks(0);
setInterval(() => cleanStaleLocks(LOCK_MAX_AGE_MS), LOCK_SCAN_INTERVAL_MS).unref();

// --- 补丁 5: Memory 目录备份/恢复 ---
const OPENCLAW_DIR = path.join(HOME_DIR, '.openclaw');
const MEMORY_DIR = path.join(OPENCLAW_DIR, 'workspace', 'memory');
const MEMORY_BACKUP_DIR = path.join(OPENCLAW_DIR, '.memory-backup');

function backupMemoryDir() {
  try {
    if (!fs.existsSync(MEMORY_DIR)) return;
    const files = fs.readdirSync(MEMORY_DIR);
    if (files.length === 0) return;
    fs.mkdirSync(MEMORY_BACKUP_DIR, { recursive: true });
    for (const file of files) {
      const src = path.join(MEMORY_DIR, file);
      const dst = path.join(MEMORY_BACKUP_DIR, file);
      try {
        const srcStat = fs.statSync(src);
        if (!srcStat.isFile()) continue;
        let dstMtime = 0;
        try { dstMtime = fs.statSync(dst).mtimeMs; } catch { /* ok */ }
        if (srcStat.mtimeMs > dstMtime) fs.copyFileSync(src, dst);
      } catch { /* 跳过 */ }
    }
  } catch { /* 忽略 */ }
}

function restoreMemoryDir() {
  try {
    if (fs.existsSync(MEMORY_DIR) && fs.readdirSync(MEMORY_DIR).length > 0) return;
    if (!fs.existsSync(MEMORY_BACKUP_DIR)) return;
    const files = fs.readdirSync(MEMORY_BACKUP_DIR);
    if (files.length === 0) return;
    fs.mkdirSync(MEMORY_DIR, { recursive: true });
    for (const file of files) {
      try { fs.copyFileSync(path.join(MEMORY_BACKUP_DIR, file), path.join(MEMORY_DIR, file)); }
      catch { /* 跳过 */ }
    }
  } catch { /* 忽略 */ }
}

restoreMemoryDir();
backupMemoryDir();
setInterval(() => backupMemoryDir(), 5 * 60 * 1000).unref();

process.stderr.write('[crash-guard] 所有补丁已应用\n');
