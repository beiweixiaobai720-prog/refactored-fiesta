// 设计关卡用的小工具：ASCII 渲染、按键回放、BFS 求解
'use strict';
const E = require('../js/engine.js');

function render(s) {
  const out = [];
  for (let y = 0; y < s.h; y++) {
    let line = '';
    for (let x = 0; x < s.w; x++) {
      const k = y * s.w + x;
      if (E.hasPlayer(s) && x === s.px && y === s.py) line += '@';
      else if (s.cells[k] === E.RED) line += 'r';
      else if (s.cells[k]) line += 'o';
      else if (x === s.gx && y === s.gy) line += '*';
      else if (x === s.ax && y === s.ay) line += 'A';
      else if (s.terrain[k] === E.STONE) line += '#';
      else if (s.terrain[k] === E.SOIL) line += '+';
      else line += '.';
    }
    out.push(line);
  }
  return out.join('\n');
}

function play(def, actions, opts = {}) {
  let s = E.parse(def);
  const frames = [render(s)];
  for (const a of actions) {
    const r = E.step(s, a);
    s = r.state;
    frames.push(render(s));
    if (s.dead || s.won) break;
  }
  return { state: s, frames };
}

function solve(def, opts = {}) {
  const maxStates = opts.maxStates || 2e6;
  const maxDepth = opts.maxDepth || 400;
  const s0 = E.parse(def);
  const seen = new Map();
  seen.set(E.key(s0), null);
  let frontier = [{ s: s0, path: '' }];
  let count = 1;
  for (let d = 0; d < maxDepth && frontier.length; d++) {
    const nextF = [];
    for (const node of frontier) {
      for (const a of ['L', 'R', 'W']) {
        const r = E.step(node.s, a);
        const ns = r.state;
        if (ns.dead) continue;
        const p = node.path + a;
        if (ns.won) return { path: p, states: count, depth: d + 1 };
        const k = E.key(ns);
        if (seen.has(k)) continue;
        seen.set(k, 1);
        count++;
        if (count > maxStates) return { path: null, states: count, depth: d, truncated: true };
        nextF.push({ s: ns, path: p });
      }
    }
    frontier = nextF;
  }
  return { path: null, states: count };
}

module.exports = { E, render, play, solve };
