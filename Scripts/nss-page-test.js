#!/usr/bin/env bun
/*
 * ImmortalWRT NSS 加速页面的回归测试。
 *
 * 用法：  bun Scripts/nss-page-test.js
 *
 * 它直接从 Settings.sh 的 heredoc 里取出 nss.js 源码来跑，不需要先构建固件 ——
 * 所以改完 Settings.sh 就能立刻验证，不必等云编译。
 *
 * 为什么值得留这个文件：这个页面的 bug 几乎全在【动态行为与边界】上，静态看
 * 代码都"像对的"。以下都是实际出过的问题，每一条都有对应的断言：
 *   ① draw() 清空 svg 后没把 bindHover() 建的准星/圆点挂回去
 *      → 页面停留 5 秒后悬停十字线永久消失，且不报错
 *   ② monotone() 在样本数 <2 时返回空串、xOf() 以 (n-1) 作分母
 *      → 单点历史产出 d=" LNaN,… LNaN,… Z"，整条曲线画不出来
 *   ③ readStatus() 无条件吞掉错误
 *      → ACL 失效/脚本缺失只表现为"图表一直空着"，提示却说"等待约 30 秒"
 *   ④ conns 数据源按"纯数字"解析，而 ECM 实际给的是
 *      "tcp X udp Y other Z total W" 文本 → 页面永远显示 "—"
 * 这些都不是语法或构建能发现的，必须跑到"第 N 次轮询之后"和"边界输入"才暴露。
 */

import { readFileSync } from 'fs';
import { dirname } from 'path';

const here = import.meta.dir ?? dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const shPath = process.argv[2] ?? `${here}/Settings.sh`;

/* ── 从 Settings.sh 的 heredoc 取 nss.js ── */
function extractPageSource(sh) {
	const norm = sh.replace(/\r\n/g, '\n');
	const m = norm.match(
		/cat > \$PKGDIR\/root\/www\/luci-static\/resources\/view\/ImmortalWRT\/nss\.js <<'EOF'\n([\s\S]*?)\nEOF\n/
	);
	if (!m) throw new Error(`未能从 ${shPath} 提取 nss.js（heredoc 标记变了？）`);
	return m[1];
}

const src = extractPageSource(readFileSync(shPath, 'utf8'));

/* ── 最小 DOM stub ──
   只需要 el.appendChild/removeChild/children/attrs/textContent/classList/
   addEventListener —— 够 render()/apply()/draw() 跑完即可。 */
class El {
	constructor(tag) {
		this.tagName = tag; this.children = []; this.attrs = {}; this._text = ''; this.parentNode = null;
	}
	get className() { return this.attrs['class'] || ''; }
	set className(v) { this.attrs['class'] = v; }
	get classList() {
		const self = this, list = () => (self.attrs['class'] || '').split(/\s+/).filter(Boolean);
		return {
			toggle(n, on) {
				const c = list(), has = c.indexOf(n) >= 0, want = on === undefined ? !has : !!on;
				if (want && !has) c.push(n);
				if (!want && has) c.splice(c.indexOf(n), 1);
				self.attrs['class'] = c.join(' ');
			},
			contains: (n) => list().indexOf(n) >= 0,
			add(n) { if (!list().includes(n)) self.attrs['class'] = list().concat(n).join(' '); },
			remove(n) { self.attrs['class'] = list().filter((x) => x !== n).join(' '); }
		};
	}
	get textContent() { return this._text; }
	set textContent(v) { this._text = String(v); }
	get firstChild() { return this.children[0] || null; }
	setAttribute(k, v) { this.attrs[k] = String(v); }
	getAttribute(k) { return k in this.attrs ? this.attrs[k] : null; }
	removeAttribute(k) { delete this.attrs[k]; }
	appendChild(c) { c.parentNode = this; this.children.push(c); return c; }
	removeChild(c) { const i = this.children.indexOf(c); if (i >= 0) this.children.splice(i, 1); return c; }
	addEventListener() {}
	querySelector() { return null; }
	getBoundingClientRect() { return { left: 0, top: 0, width: 940, height: 238 }; }
}
const document = { createElementNS: (ns, tag) => new El(tag) };

function E(tag, attrs, children) {
	const el = new El(tag);
	if (attrs) for (const k in attrs) {
		el.attrs[k] = attrs[k];
		/* 复刻 luci-base 的 dom.attr()：函数值走 addEventListener(key, fn)，
		   非函数值走 setAttribute。我们的 stub 是 El.addEventListener 空实现，
		   所以这里额外把处理器存进 el.handlers，供断言检查绑定是否真的发生
		   （否则"按钮挂了 click"这类断言会因 attrs 里看不到而误判）。 */
		if (typeof attrs[k] === 'function') {
			(el.handlers || (el.handlers = {}))[k] = attrs[k];
		}
	}
	(function add(c) {
		if (c === null || c === undefined || c === false || c === true) return;
		if (Array.isArray(c)) return c.forEach(add);
		if (typeof c === 'object') return void el.appendChild(c);
		el._text += String(c);
	})(children);
	return el;
}

/* LuCI 把 format() 挂在 String.prototype 上（luci.js 的 _() 返回普通字符串） */
String.prototype.format = function (...a) {
	let i = 0;
	return String(this).replace(/%[sd%]/g, (m) => (m === '%%' ? '%' : String(a[i++])));
};

const ui = {
	createHandlerFn: (ctx, f, ...bound) => function (...more) {
		return (typeof f === 'function' ? f : ctx[f]).apply(ctx, bound.concat(more));
	},
	/* 注意签名：addNotification(title, content, type) */
	addNotification: (title, content, type) => {
		ui._notes.push({
			text: content && content.textContent !== undefined ? content.textContent : String(content),
			type
		});
	},
	_notes: []
};
ui.Checkbox = function (value, options) { this.value = value; this.options = options || {}; };
ui.Checkbox.prototype.render = function () {
	const frame = new El('div'); frame.attrs['class'] = 'cbi-checkbox';
	const input = new El('input'); frame.appendChild(input);
	this._input = input; this.node = frame;
	return frame;
};
ui.Checkbox.prototype.setValue = function (v) { this._input.checked = (v == this.value); };
ui.Checkbox.prototype.isChecked = function () { return this._input.checked; };

/* ── rpc stub：只回 nss-status 的 stdout / rc.init 的 0 ── */
let STATUS = '', EXEC_FAIL = false;
const rpc = {
	declare: (o) => function (...args) {
		if (o.object === 'file' && o.method === 'exec') {
			if (EXEC_FAIL) return Promise.reject(new Error('Access denied'));
			if (args[0] === '/usr/libexec/ImmortalWRT/nss-status')
				return Promise.resolve({ code: 0, stdout: STATUS, stderr: '' });
			return Promise.resolve({ code: 0, stdout: '', stderr: '' });
		}
		if (o.object === 'rc') return Promise.resolve(0);
		return Promise.resolve(null);
	}
};

/* poll stub：记录注册的间隔与回调，供断言（轮询是这页唯一的持续行为） */
const poll = {
	calls: [],
	add(fn, interval) { poll.calls.push({ fn, interval }); }
};

const page = new Function('view', 'poll', 'rpc', 'dom', 'ui', 'E', '_', 'L', 'document', src)(
	{ extend: (o) => o }, poll, rpc, {}, ui, E, (s) => s,
	{ bind: (f, c) => f.bind(c) }, document
);

/* ── 断言工具 ── */
const fails = [];
const check = (name, ok, extra) => {
	if (!ok) fails.push(name);
	console.log((ok ? '  ✓ ' : '  ✗ ') + name + (!ok && extra !== undefined ? `  [${extra}]` : ''));
};

const svgHasCross = (svg) => svg.children.some((c) => c.tagName === 'line' && c.attrs['stroke-dasharray'] === '3 3');
const svgHasHoverDot = (svg) =>
	svg.children.some((c) => c.tagName === 'circle' && c.attrs.r === '4' && c.attrs.visibility === 'hidden');
const svgPaths = (svg) => svg.children.filter((c) => c.tagName === 'path');
/* 空状态提示：居中且 y = H/2（119）。不能只按 text-anchor=middle 找 ——
   有数据时时间轴中间三个标签（frac .25/.5/.75）也是 middle。 */
const svgEmptyText = (svg) =>
	(svg.children.find((c) =>
		c.tagName === 'text' && c.attrs['text-anchor'] === 'middle' && Number(c.attrs.y) === 119
	) || {}).textContent || '';
const walk = (n, out = []) => { out.push(n); n.children.forEach((c) => walk(c, out)); return out };
/* 按词匹配 class：'rw-kpis'（容器）不应被当成 'rw-kpi'（卡片） */
const hasClass = (el, cls) => new RegExp(`\\b${cls}\\b`).test(el.className);

/* nss-status 在健康状态下的输出（与脚本内各 echo 的格式一致） */
const HEALTHY = [
	'ecm=running', 'autostart=1', 'freq=748.8', 'freqlevel=mid', 'stats=ok', 'load_0=5.0'
];
const HIST3 = ['hist=1757800000:5.0,1757800030:7.5,1757800060:6.0'];

(async () => {
	console.log('═══ A. 轮询后悬停层仍在（缺陷①：draw 清空 svg 后未补挂）');
	STATUS = HEALTHY.concat(HIST3).join('\n') + '\n';
	page.render(await page.load());
	check('render 后准星在', svgHasCross(page.svg));
	check('render 后圆点在', svgHasHoverDot(page.svg));
	await page.refresh();
	check('轮询 1 次后准星仍在', svgHasCross(page.svg));
	check('轮询 1 次后圆点仍在', svgHasHoverDot(page.svg));
	check('准星 parentNode 未断链', page.svg.children.some((c) => c === page.cross && c.parentNode === page.svg));
	await page.refresh(); await page.refresh();
	check('轮询 3 次后准星仍在', svgHasCross(page.svg));
	check('悬停层叠在绘图元素之上', page.svg.children.indexOf(page.cross) > page.svg.children.indexOf(svgPaths(page.svg)[0]));

	console.log('═══ B. 单点历史不产生非法坐标（缺陷②：NaN）');
	STATUS = HEALTHY.concat(['hist=1757800000:5.0']).join('\n') + '\n';
	page.st = await page.load(); page.parseHist(page.st); page.draw();
	const dsOne = svgPaths(page.svg).map((p) => p.attrs.d || '');
	check('路径无 NaN/Infinity', !dsOne.some((d) => /NaN|Infinity/.test(d)), JSON.stringify(dsOne).slice(0, 80));
	const single = page.svg.children.filter((c) => c.tagName === 'circle' && c.attrs.r === '4.5');
	check('画出了单点标记', single.length === 1);
	check('单点坐标有限', single.length === 1 && isFinite(+single[0].attrs.cx) && isFinite(+single[0].attrs.cy));
	check('单点时不画叠在一起的刻度',
		page.svg.children.filter((c) => c.tagName === 'text' && /^\d{2}:\d{2}/.test(c.textContent)).length === 0);

	console.log('═══ C. 多点恢复正常曲线');
	STATUS = HEALTHY.concat(['hist=1757800000:5.0,1757800030:7.5']).join('\n') + '\n';
	page.st = await page.load(); page.parseHist(page.st); page.draw();
	const dsTwo = svgPaths(page.svg).map((p) => p.attrs.d || '');
	check('曲线路径非空且无 NaN', dsTwo.length === 2 && dsTwo.every((d) => d && !/NaN/.test(d)));
	check('曲线为贝塞尔 C 段', dsTwo.some((d) => /C/.test(d)));

	console.log('═══ D. 采集失败不再静默（缺陷③）');
	EXEC_FAIL = true; ui._notes.length = 0;
	page.st = await page.load(); page.parseHist(page.st); page.draw(); page.apply();
	check('失败时弹出一次通知', ui._notes.length === 1, '次数 ' + ui._notes.length);
	check('通知含失败原因', /Access denied/.test(ui._notes[0] ? ui._notes[0].text : ''), ui._notes[0]?.text);
	check('通知级别为 error', ui._notes[0] && ui._notes[0].type === 'error');
	await page.refresh(); await page.refresh();
	check('后续轮询不重复弹通知', ui._notes.length === 1, '次数 ' + ui._notes.length);
	check('空图提示指向失败而非"等待 30 秒"', /失败/.test(svgEmptyText(page.svg)), svgEmptyText(page.svg));
	EXEC_FAIL = false; ui._notes.length = 0;
	page.st = await page.load(); page.apply();
	check('恢复后不再提示', ui._notes.length === 0);

	console.log('═══ E. debugfs 不可用与"尚未采到"要区分');
	STATUS = ['ecm=running', 'autostart=1', 'freq=748.8', 'freqlevel=mid', 'stats=unavailable'].join('\n') + '\n';
	page.st = await page.load(); page.parseHist(page.st); page.draw();
	check('提示指明 debugfs 原因', /debugfs/.test(svgEmptyText(page.svg)), svgEmptyText(page.svg));

	STATUS = HEALTHY.concat(HIST3).join('\n') + '\n';
	page.st = await page.load(); page.parseHist(page.st); page.draw();
	check('有数据时不出现空图提示', svgEmptyText(page.svg) === '', svgEmptyText(page.svg));

	console.log('═══ F. 频率档位按钮');
	page.st = await page.load(); page.apply();
	check('恰好 2 个档位按钮', page.modeEl.children.length === 2);
	check('标签为 748.8/1497.6 MHz',
		page.modeEl.children[0].textContent === '748.8 MHz' && page.modeEl.children[1].textContent === '1497.6 MHz');
	check('按钮类含 btn', page.modeEl.children.every((b) => /\bbtn\b/.test(b.className)));
	/* ★ 回归：曾用 ui.createHandlerFn(self, function () {...}) —— 该工厂内部读
	   arguments[args.length].currentTarget，传匿名函数时为 undefined → 抛 TypeError，
	   点击完全无反应。故这里断言 click 是自带事件处理的普通函数：能接收 ev 且自行
	   做禁用/恢复，不依赖外部工厂。
	   判定方式：给一个假的 ev（含 currentTarget）调用它，若抛错或没消费 ev 即失败。 */
	check('档位按钮 click 自带事件处理（不依赖 createHandlerFn）', page.modeEl.children.every((b) => {
		if (typeof b.attrs.click !== 'function') return false;
		if (b.attrs.click.length < 1) return false;      // 未声明 ev 形参
		const fake = { currentTarget: b, preventDefault() {} };
		try {
			const r = b.attrs.click(fake);
			if (r && typeof r.then === 'function') r.catch(() => {});
			return true;
		} catch (e) { return false; }
	}));
	check('type=button（不误触发表单提交）', page.modeEl.children.every((b) => b.attrs.type === 'button'));
	check('mid 档高亮', page.modeBtn.mid.classList.contains('cbi-button-action'));
	check('high 档未高亮', !page.modeBtn.high.classList.contains('cbi-button-action'));
	check('未用 [disabled] 标当前档（主题会给它加 opacity，像失效）',
		page.modeEl.children[0].getAttribute('disabled') === null);
	page.st = Object.assign({}, page.st, { freqlevel: 'high' }); page.apply();
	check('切 high 后高亮反转',
		page.modeBtn.high.classList.contains('cbi-button-action') &&
		!page.modeBtn.mid.classList.contains('cbi-button-action'));
	check('classList 切换未抹掉 btn 类', page.modeBtn.high.className.split(/\s+/).includes('btn'));

	console.log('═══ G. 加速连接数（缺陷④：数据源是文本而非纯数字）');
	STATUS = HEALTHY.concat(['conns=1234']).concat(HIST3).join('\n') + '\n';
	page.st = await page.load(); page.apply();
	check('有值时显示数值', page.connEl.textContent === '1234', page.connEl.textContent);
	STATUS = HEALTHY.concat(['conns=0']).concat(HIST3).join('\n') + '\n';
	page.st = await page.load(); page.apply();
	check('为 0 时显示 0（而非 —）', page.connEl.textContent === '0', page.connEl.textContent);
	STATUS = HEALTHY.concat(HIST3).join('\n') + '\n';     // 无 conns 行 = ECM 未加载
	page.st = await page.load(); page.apply();
	check('取不到时显示 —（而非 0）', page.connEl.textContent === '—', page.connEl.textContent);
	STATUS = HEALTHY.concat(['conns=']).concat(HIST3).join('\n') + '\n';
	page.st = await page.load(); page.apply();
	check('空值显示 —', page.connEl.textContent === '—', page.connEl.textContent);

	console.log('═══ H. 数据源字段与页面消费点一一对齐');
	const emitted = ['ecm', 'autostart', 'freq', 'freqlevel', 'stats', 'conns', 'hist'];
	const unused = emitted.filter((k) => !new RegExp('(st|this\\.st)\\.' + k).test(src));
	check('无页面未消费的输出字段', unused.length === 0, unused.join(', '));

	console.log('═══ I. 基础状态渲染');
	STATUS = HEALTHY.concat(['conns=42']).concat(HIST3).join('\n') + '\n';
	page.st = await page.load(); page.parseHist(page.st); page.draw(); page.apply();
	check('徽章=运行中', page.tagTxt.textContent === '运行中', page.tagTxt.textContent);
	check('硬件加速开关选中', page.cbRun.isChecked() === true);
	check('自启开关选中', page.cbAuto.isChecked() === true);
	check('频率读数=748.8', page.freqEl.textContent === '748.8', String(page.freqEl.textContent));
	check('实时负载=5.0', page.nowEl.textContent === '5.0', String(page.nowEl.textContent));
	check('历史点解析 3 个', page.hist.length === 3, String(page.hist.length));

	console.log('═══ J. KPI 区 DOM 结构');
	const res = page.render(await page.load());
	const nodes = walk(res);
	const labels = nodes.filter((n) => n.tagName === 'em').map((n) => n.textContent);
	const units = nodes.filter((n) => n.tagName === 'u').map((n) => n.textContent);
	check('KPI 卡片 4 个', nodes.filter((n) => hasClass(n, 'rw-kpi')).length === 4);
	check('四个 KPI 标签齐全',
		['频率档位', 'NSS 频率', '加速连接数', '开机自启'].every((l) => labels.includes(l)),
		JSON.stringify(labels));
	check('连接数元素在 DOM 树中', nodes.includes(page.connEl));
	check('连接数有「条」单位', units.includes('条'), JSON.stringify(units));
	check('频率有 MHz 单位', units.includes('MHz'));
	check('连接数容器为 .rw-v', page.connEl.parentNode && page.connEl.parentNode.className === 'rw-v');

	console.log('═══ K. 轮询注册（这页唯一的持续行为）');
	check('注册了轮询', poll.calls.length >= 1, '次数 ' + poll.calls.length);
	check('轮询间隔为 5 秒', poll.calls.every((c) => c.interval === 5),
		JSON.stringify(poll.calls.map((c) => c.interval)));
	check('轮询回调可执行且返回 Promise', (() => {
		const r = poll.calls[0].fn();
		return r && typeof r.then === 'function';
	})());

	console.log('');
	if (fails.length) {
		console.log(`❌ 失败 ${fails.length} 项:`);
		fails.forEach((f) => console.log('   - ' + f));
		process.exit(1);
	}
	console.log(`✅ 全部通过（${shPath}）`);
})();
