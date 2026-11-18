#import "DashboardHTML.h"

@implementation DashboardHTML

+ (NSString *)htmlTemplate {
    return @R"HTML(<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<style>
  :root {
    --bg: #f5f5f7;
    --card: #ffffff;
    --text: #1d1d1f;
    --sub: #6e6e73;
    --border: rgba(0, 0, 0, 0.08);
    --accent: #007aff;
    --green: #28cd41;
    --green-bg: rgba(40, 205, 65, 0.14);
    --orange: #ff9500;
    --red: #ff3b30;
    --red-bg: rgba(255, 59, 48, 0.14);
    --track: rgba(0, 0, 0, 0.08);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #1e1e20;
      --card: #2a2a2d;
      --text: #f5f5f7;
      --sub: #a1a1a6;
      --border: rgba(255, 255, 255, 0.1);
      --accent: #0a84ff;
      --green: #30d158;
      --green-bg: rgba(48, 209, 88, 0.18);
      --orange: #ff9f0a;
      --red: #ff453a;
      --red-bg: rgba(255, 69, 58, 0.18);
      --track: rgba(255, 255, 255, 0.12);
    }
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", sans-serif;
    background: var(--bg);
    color: var(--text);
    font-size: 13px;
    line-height: 1.4;
    -webkit-user-select: none;
    overflow-x: hidden;
  }
  .header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 12px 14px 10px;
    border-bottom: 1px solid var(--border);
  }
  .title { font-weight: 600; font-size: 14px; display: flex; align-items: center; gap: 6px; }
  .actions { display: flex; align-items: center; gap: 8px; }
  .time-lbl { font-size: 11px; color: var(--sub); }
  .icon-btn {
    background: transparent;
    border: 1px solid var(--border);
    color: var(--text);
    border-radius: 6px;
    padding: 4px 8px;
    font-size: 11px;
    cursor: pointer;
  }
  .icon-btn:hover { background: var(--track); }
  .icon-btn:disabled { opacity: 0.5; cursor: default; }
  .content {
    padding: 10px 14px;
    max-height: 460px;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .card {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 11px 12px;
  }
  .card-top {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 6px;
  }
  .prov-name { font-weight: 600; font-size: 13px; }
  .badge {
    font-size: 10px;
    padding: 2px 6px;
    border-radius: 4px;
    max-width: 210px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .badge.ok { background: var(--green-bg); color: var(--green); }
  .badge.err { background: var(--red-bg); color: var(--red); }
  .badge.pending { background: var(--track); color: var(--sub); }
  .rem-row {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    margin-bottom: 6px;
  }
  .rem-val { font-size: 18px; font-weight: 700; font-variant-numeric: tabular-nums; }
  .used-val { font-size: 11px; color: var(--sub); font-variant-numeric: tabular-nums; }
  .bar-track {
    height: 6px;
    background: var(--track);
    border-radius: 3px;
    overflow: hidden;
    margin-bottom: 7px;
  }
  .bar-fill { height: 100%; border-radius: 3px; transition: width 0.3s ease; }
  .meta-row {
    display: flex;
    justify-content: space-between;
    font-size: 11px;
    color: var(--sub);
    font-variant-numeric: tabular-nums;
  }
  .chart-head {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 8px;
  }
  select {
    background: var(--bg);
    color: var(--text);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 3px 6px;
    font-size: 11px;
  }
  .footer {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 8px 14px 10px;
    border-top: 1px solid var(--border);
    font-size: 11px;
    color: var(--sub);
  }
  .link-btn {
    background: none;
    border: none;
    color: var(--sub);
    font-size: 11px;
    cursor: pointer;
  }
  .link-btn:hover { color: var(--text); }

  /* Settings */
  .field-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 8px;
  }
  .field-row:last-child { margin-bottom: 0; }
  input[type="text"] {
    width: 100%;
    background: var(--bg);
    color: var(--text);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 5px 8px;
    font-size: 12px;
    margin-top: 4px;
    -webkit-user-select: text;
  }
  .prov-edit-top {
    display: flex;
    gap: 8px;
    align-items: center;
    margin-bottom: 6px;
  }
  .prov-edit-top input[type="text"] { width: 130px; margin-top: 0; }
  .chk { display: flex; align-items: center; gap: 4px; font-size: 11px; color: var(--sub); margin-top: 6px; }
  .primary-btn {
    background: var(--accent);
    color: #fff;
    border: none;
    border-radius: 6px;
    padding: 4px 10px;
    font-size: 12px;
    font-weight: 500;
    cursor: pointer;
  }
  .danger-btn {
    background: transparent;
    border: none;
    color: var(--red);
    font-size: 11px;
    cursor: pointer;
    margin-left: auto;
  }
</style>
</head>
<body>
  <div id="app"></div>

  <script>
    let STATE = null;
    let VIEW = 'dashboard';
    let CHART_FILTER = 'ALL';
    let CHART_SOURCE = 'remote';
    let DRAFT = null;

    function fmtGB(bytes, dec = 1) {
      if (bytes == null) return '--';
      const gb = bytes / 1073741824;
      if (Math.abs(gb) >= 1 || bytes === 0) return gb.toFixed(dec) + ' GB';
      const mb = bytes / 1048576;
      return mb.toFixed(0) + ' MB';
    }

    function esc(s) {
      return String(s || '').replace(/[&<>"']/g, c => ({
        '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
      }[c]));
    }

    function post(action, payload = {}) {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge) {
        window.webkit.messageHandlers.bridge.postMessage({ action, payload });
      }
    }

    window.updateState = function(newState) {
      STATE = newState;
      if (VIEW === 'dashboard') render();
    };

    function render() {
      if (!STATE) return;
      if (VIEW === 'settings') {
        renderSettings();
      } else {
        renderDashboard();
      }
    }

    function renderDashboard() {
      const providers = STATE.statuses || [];
      let cardsHtml = providers.length === 0
        ? `<div class="card" style="color:var(--sub);font-size:12px;">尚未配置任何订阅源，请点击右上角「设置」→「+ 添加机场」填入订阅链接。</div>`
        : providers.map(st => {
        const badgeCls = st.health === 'ok' ? 'ok' : (st.health === 'pending' ? 'pending' : 'err');
        const badgeText = st.health === 'ok' ? '正常' : (st.health === 'pending' ? '等待中' : st.health);

        let bodyHtml = `<div style="font-size:12px;color:var(--sub);margin-top:4px;">暂无流量数据，请在设置中检查或更新订阅链接。</div>`;
        if (st.latest) {
          const ratio = st.latest.total > 0 ? Math.min(1, st.latest.used / st.latest.total) : 0;
          const pct = (ratio * 100).toFixed(1);
          const color = ratio > 0.9 ? 'var(--red)' : (ratio > 0.75 ? 'var(--orange)' : 'var(--accent)');
          const expText = st.latest.expireLabel ? `到期 ${esc(st.latest.expireLabel)}` : '不限时';
          bodyHtml = `
            <div class="rem-row">
              <div class="rem-val">剩余 ${fmtGB(st.latest.remaining)}</div>
              <div class="used-val">已用 ${fmtGB(st.latest.used)} / ${fmtGB(st.latest.total, 0)}</div>
            </div>
            <div class="bar-track"><div class="bar-fill" style="width:${pct}%;background:${color};"></div></div>
            <div class="meta-row">
              <span>24h: ${fmtGB(st.usage24h)} &nbsp;·&nbsp; 今日: ${fmtGB(st.usageToday)}</span>
              <span>${expText}</span>
            </div>
            <div class="meta-row" style="margin-top:3px;color:var(--accent);">
              <span>本机 Clash 实测: 24h ${fmtGB(st.local24h || 0)} &nbsp;·&nbsp; 今日 ${fmtGB(st.localToday || 0)}</span>
            </div>
          `;
        }
        return `
          <div class="card">
            <div class="card-top">
              <span class="prov-name">${esc(st.name)}</span>
              <span class="badge ${badgeCls}" title="${esc(badgeText)}">${esc(badgeText)}</span>
            </div>
            ${bodyHtml}
          </div>
        `;
      }).join('');

      // Chart data
      const useLocal = (CHART_SOURCE === 'local');
      const days = (CHART_FILTER === 'ALL')
        ? (useLocal ? (STATE.allLocalDaily7d || []) : (STATE.allDaily7d || []))
        : (useLocal
            ? ((providers.find(p => p.id === CHART_FILTER) || {}).localDaily7d || STATE.allLocalDaily7d || [])
            : ((providers.find(p => p.id === CHART_FILTER) || {}).daily7d || STATE.allDaily7d || []));
      const maxGB = Math.max(1, ...days.map(d => d.bytes / 1073741824)) * 1.18;

      const W = 330, H = 115, padL = 26, padR = 6, padT = 16, padB = 20;
      const plotW = W - padL - padR;
      const plotH = H - padT - padB;
      const barW = 24;
      const step = days.length > 0 ? plotW / days.length : plotW;

      let svgBars = '';
      // Grid lines
      for (let i = 0; i <= 2; i++) {
        const y = padT + plotH * (1 - i / 2);
        const val = (maxGB * i / 2).toFixed(0) + 'G';
        svgBars += `<line x1="${padL}" y1="${y}" x2="${W - padR}" y2="${y}" stroke="var(--border)" stroke-dasharray="2,2" />`;
        svgBars += `<text x="${padL - 4}" y="${y + 3}" text-anchor="end" fill="var(--sub)" font-size="9">${val}</text>`;
      }

      days.forEach((d, idx) => {
        const gb = d.bytes / 1073741824;
        const bh = Math.max(2, (gb / maxGB) * plotH);
        const cx = padL + step * idx + step / 2;
        const x = cx - barW / 2;
        const y = padT + plotH - bh;
        svgBars += `<rect x="${x}" y="${y}" width="${barW}" height="${bh}" rx="4" fill="var(--accent)" opacity="0.88"><title>${esc(d.label)}: ${gb.toFixed(2)} GB</title></rect>`;
        if (gb >= 0.05) {
          svgBars += `<text x="${cx}" y="${y - 4}" text-anchor="middle" fill="var(--sub)" font-size="9">${gb.toFixed(1)}</text>`;
        }
        svgBars += `<text x="${cx}" y="${H - 4}" text-anchor="middle" fill="var(--sub)" font-size="10">${esc(d.label)}</text>`;
      });

      const filterOpts = `<option value="ALL" ${CHART_FILTER === 'ALL' ? 'selected' : ''}>全部合计</option>` +
        providers.map(p => `<option value="${esc(p.id)}" ${CHART_FILTER === p.id ? 'selected' : ''}>${esc(p.name)}</option>`).join('');

      document.getElementById('app').innerHTML = `
        <div class="header">
          <div class="title">📊 VPN 流量监控</div>
          <div class="actions">
            <span class="time-lbl">${esc(STATE.lastRefreshLabel || '')}</span>
            <button class="icon-btn" onclick="post('refresh')" ${STATE.isRefreshing ? 'disabled' : ''}>${STATE.isRefreshing ? '刷新中...' : '刷新'}</button>
            <button class="icon-btn" onclick="openSettings()">设置</button>
          </div>
        </div>
        <div class="content">
          ${cardsHtml}
          <div class="card">
            <div class="chart-head">
              <span class="prov-name">7 天每日消耗趋势</span>
              <div style="display:flex;gap:6px;align-items:center;">
                <select onchange="CHART_SOURCE=this.value;render();">
                  <option value="remote" ${CHART_SOURCE==='remote'?'selected':''}>账单同步</option>
                  <option value="local" ${CHART_SOURCE==='local'?'selected':''}>本机实测</option>
                </select>
                <select onchange="CHART_FILTER=this.value;render();">${filterOpts}</select>
              </div>
            </div>
            <svg width="100%" viewBox="0 0 ${W} ${H}">${svgBars}</svg>
          </div>
        </div>
        <div class="footer">
          <span>${STATE.config.refreshIntervalMinutes <= 0 ? '仅手动刷新' : (STATE.config.refreshIntervalMinutes >= 60 ? '每 ' + (STATE.config.refreshIntervalMinutes / 60) + ' 小时自动抓取' : '每 ' + STATE.config.refreshIntervalMinutes + ' 分钟自动抓取')}</span>
          <button class="link-btn" onclick="post('quit')">退出应用</button>
        </div>
      `;
    }

    function openSettings() {
      DRAFT = JSON.parse(JSON.stringify(STATE.config));
      VIEW = 'settings';
      render();
    }

    function saveSettings() {
      post('saveConfig', DRAFT);
      VIEW = 'dashboard';
      render();
    }

    function addProvider() {
      DRAFT.providers.push({
        id: 'vpn_' + Date.now(),
        name: '新机场',
        subscriptionURL: '',
        useProxy: false,
        enabled: true
      });
      render();
    }

    function removeProvider(idx) {
      DRAFT.providers.splice(idx, 1);
      render();
    }

    function renderSettings() {
      const provHtml = DRAFT.providers.map((p, idx) => {
        const urlInput = p.keychainService
          ? `<div style="font-size:11px;color:var(--sub);margin-top:4px;">🔑 从系统钥匙串读取 (${esc(p.keychainService)}) <button class="link-btn" style="color:var(--accent);" onclick="delete DRAFT.providers[${idx}].keychainService;delete DRAFT.providers[${idx}].keychainAccount;render();">改用链接</button></div>`
          : `<input type="text" value="${esc(p.subscriptionURL)}" placeholder="https://..." oninput="DRAFT.providers[${idx}].subscriptionURL=this.value" />`;

        return `
          <div class="card">
            <div class="prov-edit-top">
              <input type="text" value="${esc(p.name)}" oninput="DRAFT.providers[${idx}].name=this.value" />
              <label class="chk" style="margin-top:0;"><input type="checkbox" ${p.enabled ? 'checked' : ''} onchange="DRAFT.providers[${idx}].enabled=this.checked" /> 启用</label>
              <button class="danger-btn" onclick="removeProvider(${idx})">删除</button>
            </div>
            ${urlInput}
            <label class="chk"><input type="checkbox" ${p.useProxy ? 'checked' : ''} onchange="DRAFT.providers[${idx}].useProxy=this.checked" /> 通过本地代理 (${esc(DRAFT.proxyHost)}:${DRAFT.proxyPort}) 抓取</label>
          </div>
        `;
      }).join('');

      const primaryOpts = `<option value="" ${!DRAFT.primaryProviderId ? 'selected' : ''}>全部合计</option>` +
        DRAFT.providers.map(p => `<option value="${esc(p.id)}" ${DRAFT.primaryProviderId === p.id ? 'selected' : ''}>${esc(p.name)}</option>`).join('');

      document.getElementById('app').innerHTML = `
        <div class="header">
          <button class="icon-btn" onclick="VIEW='dashboard';render();">← 返回</button>
          <div class="title">订阅与抓取设置</div>
          <button class="primary-btn" onclick="saveSettings()">保存</button>
        </div>
        <div class="content">
          <div class="card">
            <div class="field-row">
              <span>自动抓取间隔</span>
              <select onchange="DRAFT.refreshIntervalMinutes=parseInt(this.value,10)">
                <option value="0" ${DRAFT.refreshIntervalMinutes===0?'selected':''}>手动（仅点击刷新）</option>
                <option value="5" ${DRAFT.refreshIntervalMinutes===5?'selected':''}>5 分钟（测试用）</option>
                <option value="60" ${DRAFT.refreshIntervalMinutes===60?'selected':''}>1 小时</option>
                <option value="480" ${DRAFT.refreshIntervalMinutes===480?'selected':''}>8 小时（推荐）</option>
                <option value="1440" ${DRAFT.refreshIntervalMinutes===1440?'selected':''}>24 小时</option>
              </select>
            </div>
            <div style="font-size:11px;color:var(--sub);margin:-2px 0 8px;">提示：日常推荐 8 小时自动抓取，或设为手动按需点击右上角「刷新」。</div>
            <div class="field-row">
              <span>菜单栏主显示</span>
              <select onchange="DRAFT.primaryProviderId=this.value || null">${primaryOpts}</select>
            </div>
          </div>
          <div style="display:flex;justify-content:space-between;align-items:center;">
            <span style="font-weight:600;">机场订阅源</span>
            <button class="icon-btn" onclick="addProvider()">+ 添加机场</button>
          </div>
          ${provHtml}
        </div>
      `;
    }
  </script>
</body>
</html>)HTML";
}

@end
