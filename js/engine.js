/*
 * 三生万物 · 规则内核
 * 纯逻辑，无渲染。浏览器下挂到 window.Engine，Node 下 module.exports。
 *
 * 世界每回合的顺序：
 *   1. 万物演化一代（B3/S23），你所在的格子也算作一个“活着的邻居”
 *   2. 你行动（左 / 右 / 等待），遇一格高的台阶会自动攀上
 *   3. 重力：脚下无物则下坠一格
 * 因为演化发生在你行动之前，所以“预见”显示的下一代与你接下来按哪个键无关。
 */
(function (root) {
  'use strict';

  var AIR = 0, STONE = 1, SOIL = 2;
  // 细胞取值：0 无；1 墨；2 朱（与你同源）；3 墨，但你曾是它的“第三位”
  var INK = 1, RED = 2, SEAL = 3;

  function parse(def) {
    var rows = def.map.slice();
    var h = rows.length, w = 0, i, x, y;
    for (i = 0; i < h; i++) w = Math.max(w, rows[i].length);
    var terrain = new Uint8Array(w * h);
    var cells = new Uint8Array(w * h);
    var px = -1, py = -1, gx = -1, gy = -1, ax = -1, ay = -1;
    for (y = 0; y < h; y++) {
      for (x = 0; x < w; x++) {
        var c = rows[y][x] || '.';
        var k = y * w + x;
        switch (c) {
          case '#': terrain[k] = STONE; break;
          case '+': terrain[k] = SOIL; break;
          case 'o': terrain[k] = SOIL; cells[k] = INK; break;
          case 'r': terrain[k] = SOIL; cells[k] = RED; break;
          case '@': px = x; py = y; break;
          case '&': px = x; py = y; terrain[k] = SOIL; break;   // 站在沃土上出生
          case '*': gx = x; gy = y; break;
          case '%': gx = x; gy = y; terrain[k] = SOIL; break;   // 沃土上的归处
          case 'A': ax = x; ay = y; break;                      // 祭台（终章）
          default: terrain[k] = AIR;
        }
      }
    }
    return {
      w: w, h: h, terrain: terrain, cells: cells,
      px: px, py: py, gx: gx, gy: gy, ax: ax, ay: ay,
      gen: 0, births: 0, myBirths: 0,
      dead: false, won: false, released: false,
      glider: def.glider || null
    };
  }

  function clone(s) {
    return {
      w: s.w, h: s.h, terrain: s.terrain, cells: s.cells.slice(),
      px: s.px, py: s.py, gx: s.gx, gy: s.gy, ax: s.ax, ay: s.ay,
      gen: s.gen, births: s.births, myBirths: s.myBirths,
      dead: s.dead, won: s.won, released: s.released,
      glider: s.glider
    };
  }

  function hasPlayer(s) { return !s.released && s.px >= 0; }

  // 计算下一代。返回 { cells, born:[k...], died:[k...], mine:[k...] }
  function lifeStep(s) {
    var w = s.w, h = s.h, cells = s.cells, terrain = s.terrain;
    var next = new Uint8Array(w * h);
    var born = [], died = [], mine = [];
    var pk = hasPlayer(s) ? s.py * w + s.px : -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var k = y * w + x;
        if (terrain[k] !== SOIL || k === pk) { if (cells[k]) died.push(k); continue; }
        var n = 0, reds = 0, nearMe = false;
        for (var dy = -1; dy <= 1; dy++) {
          var yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            if (!dx && !dy) continue;
            var xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            var kk = yy * w + xx;
            var v = cells[kk];
            if (v) { n++; if (v === RED) reds++; }
            else if (kk === pk) { n++; reds++; nearMe = true; }
          }
        }
        var cur = cells[k];
        if (cur) {
          if (n === 2 || n === 3) next[k] = cur; else died.push(k);
        } else if (n === 3) {
          next[k] = reds >= 2 ? RED : (nearMe ? SEAL : INK);
          born.push(k);
          if (nearMe) mine.push(k);
        }
      }
    }
    return { cells: next, born: born, died: died, mine: mine };
  }

  function solidAt(s, x, y) {
    if (x < 0 || x >= s.w) return true;
    if (y < 0) return true;
    if (y >= s.h) return false;
    var k = y * s.w + x;
    return s.terrain[k] === STONE || s.cells[k] !== 0;
  }

  // 让你化作滑翔者：以祭台为中心的 3x3 内放下五个朱色细胞
  var GLIDERS = {
    // 右上方向飞行
    ur: [[0, 0], [1, 0], [2, 0], [2, 1], [1, 2]],
    // 右下方向飞行
    dr: [[1, 0], [2, 1], [0, 2], [1, 2], [2, 2]],
    ul: [[0, 0], [1, 0], [2, 0], [0, 1], [1, 2]],
    dl: [[1, 0], [0, 1], [0, 2], [1, 2], [2, 2]]
  };

  function release(s) {
    var g = GLIDERS[s.glider || 'ur'];
    var ox = s.px - 1, oy = s.py - 1;
    for (var i = 0; i < g.length; i++) {
      var x = ox + g[i][0], y = oy + g[i][1];
      if (x < 0 || y < 0 || x >= s.w || y >= s.h) continue;
      var k = y * s.w + x;
      if (s.terrain[k] === SOIL) s.cells[k] = RED;
    }
    s.released = true;
  }

  // action: 'L' | 'R' | 'W'
  function step(s, action) {
    var n = clone(s);
    if (n.dead || n.won) return { state: n, born: [], died: [], mine: [], moved: false, climbed: false, fell: false, bumped: false };
    var r = lifeStep(n);
    n.cells = r.cells;
    n.gen++;
    n.births += r.born.length;
    n.myBirths += r.mine.length;
    var moved = false, climbed = false, fell = false, bumped = false;
    if (hasPlayer(n)) {
      var dir = action === 'L' ? -1 : action === 'R' ? 1 : 0;
      if (dir) {
        var tx = n.px + dir;
        var supported = solidAt(n, n.px, n.py + 1);
        if (!solidAt(n, tx, n.py)) { n.px = tx; moved = true; }
        else if (supported && !solidAt(n, n.px, n.py - 1) && !solidAt(n, tx, n.py - 1)) {
          n.px = tx; n.py -= 1; moved = true; climbed = true;
        } else bumped = true;
      }
      if (!solidAt(n, n.px, n.py + 1)) { n.py += 1; fell = true; }
      if (n.py >= n.h) { n.dead = true; }
      else if (n.px === n.gx && n.py === n.gy && !n.released) { n.won = true; }
      else if (n.px === n.ax && n.py === n.ay) { release(n); }
    } else if (n.released && n.gx >= 0 && n.cells[n.gy * n.w + n.gx]) {
      n.won = true;
    }
    return { state: n, born: r.born, died: r.died, mine: r.mine, moved: moved, climbed: climbed, fell: fell, bumped: bumped };
  }

  function key(s) {
    // 用于求解器去重
    var str = s.px + ',' + s.py + ',' + (s.released ? 1 : 0) + ':';
    var c = s.cells;
    for (var i = 0; i < c.length; i++) if (c[i]) str += i.toString(36) + ' ';
    return str;
  }

  // 纯粹的生命游戏（无你），供标题与终幕使用。环面之外皆死。
  function bareStep(cells, w, h) {
    var next = new Uint8Array(w * h);
    var births = 0;
    for (var y = 0; y < h; y++) {
      var y0 = y > 0 ? y - 1 : y, y1 = y < h - 1 ? y + 1 : y;
      for (var x = 0; x < w; x++) {
        var n = 0, x0 = x > 0 ? x - 1 : x, x1 = x < w - 1 ? x + 1 : x;
        for (var yy = y0; yy <= y1; yy++) {
          var row = yy * w;
          for (var xx = x0; xx <= x1; xx++) if (cells[row + xx]) n++;
        }
        var k = y * w + x;
        if (cells[k]) { n--; if (n === 2 || n === 3) next[k] = cells[k]; }
        else if (n === 3) { next[k] = 1; births++; }
      }
    }
    return { cells: next, births: births };
  }

  var Engine = {
    AIR: AIR, STONE: STONE, SOIL: SOIL, INK: INK, RED: RED, SEAL: SEAL,
    GLIDERS: GLIDERS,
    parse: parse, clone: clone, step: step, lifeStep: lifeStep,
    solidAt: solidAt, key: key, bareStep: bareStep, hasPlayer: hasPlayer
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = Engine;
  else root.Engine = Engine;
})(this);
