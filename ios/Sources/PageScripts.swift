import Foundation

/// 页面注入脚本：解析题目、点选、翻页、清遮罩
enum PageScripts {

    /// 解析全部题目
    static let parse = """
    () => {
      const pageOf = (el) => {
        const fs = el.closest('fieldset[pg]');
        return fs ? parseInt(fs.getAttribute('pg')) || 1 : 1;
      };
      const txt = (el) => (el ? (el.innerText || el.textContent || '').trim() : '');
      const out = [];
      document.querySelectorAll('div.field[topic]').forEach(f => {
        const topic = parseInt(f.getAttribute('topic'));
        const type = parseInt(f.getAttribute('type'));
        const titleEl = f.querySelector('.topichtml, .field-label');
        const q = {
          topic, type, pg: pageOf(f),
          required: f.getAttribute('req') === '1' || !!f.querySelector('.req'),
          title: txt(titleEl) || txt(f).slice(0, 120),
          options: [], rows: [], scale: [], min: 0, max: 0
        };
        f.querySelectorAll('.label[for], div.label[for]').forEach(lab => {
          const forId = lab.getAttribute('for') || '';
          const m = forId.match(/_([0-9]+)$/);
          if (!m) return;
          const value = m[1];
          if (q.options.some(o => o.value === value)) return;
          const t = txt(lab);
          const isOther = /其他|其它/.test(t);
          q.options.push({
            value, text: t, isOther,
            otherInput: isOther ? ('tqq' + topic + '_' + value) : ''
          });
        });
        const tip = f.querySelector('.minmax, .multi-tip');
        if (tip) {
          const t = txt(tip);
          const mn = t.match(/(?:最少|至少)[^0-9]{0,4}([0-9]+)/);
          const mx = t.match(/(?:最多|至多)[^0-9]{0,4}([0-9]+)/);
          if (mn) q.min = parseInt(mn[1]);
          if (mx) q.max = parseInt(mx[1]);
        }
        const rows = f.querySelectorAll('tr[fid]');
        if (rows.length) {
          const scale = [];
          f.querySelectorAll('table.matrix-rating thead a[dval]').forEach(h => {
            const dv = h.getAttribute('dval');
            if (dv) scale.push(dv);
          });
          rows.forEach((tr, i) => {
            const fid = tr.getAttribute('fid');
            if (!fid) return;
            const dvals = [];
            tr.querySelectorAll('a[dval]').forEach(a => dvals.push(a.getAttribute('dval')));
            q.rows.push({
              fid, index: i,
              text: txt(tr.querySelector('td:first-child, .matrix-row-title')),
              dvals: dvals.length ? dvals : ['1','2','3','4','5']
            });
          });
          q.scale = scale.length ? scale : ['1','2','3','4','5'];
        }
        if (q.options.length || q.rows.length) out.push(q);
      });
      return out;
    }
    """

    /// 清掉 layui 遮罩层（会挡住提交按钮）
    static let clearOverlay = """
    () => {
      let n = 0;
      document.querySelectorAll(
        '.layui-layer-shade, .layui-layer-page, .layui-layer-dialog, .layui-layer-loading'
      ).forEach(e => { e.remove(); n++; });
      document.body.style.overflow = '';
      return n;
    }
    """

    /// 点某个选项（label）
    static func clickLabel(topic: Int, value: String) -> String {
        """
        () => {
          const el = document.querySelector("div.field[topic='\(topic)'] div.label[for='q\(topic)_\(value)']")
                  || document.querySelector('#q\(topic)_\(value)');
          if (!el) return false;
          el.click();
          return true;
        }
        """
    }

    /// 点矩阵格子
    static func clickMatrix(fid: String, dval: String) -> String {
        """
        () => {
          const el = document.querySelector("tr[fid='\(fid)'] a[dval='\(dval)']");
          if (!el) return false;
          el.click();
          return true;
        }
        """
    }

    /// 填「其他」输入框
    static func fillOther(topic: Int, value: String, text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        return """
        () => {
          const el = document.querySelector('#tqq\(topic)_\(value)');
          if (!el) return false;
          el.focus();
          el.value = '\(escaped)';
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          el.blur();
          return true;
        }
        """
    }

    /// 翻下一页
    static let nextPage = """
    () => {
      const el = document.querySelector("a[onclick*='show_next_page'], #btnNext");
      if (!el) return false;
      el.click();
      return true;
    }
    """

    /// 点提交
    static let submit = """
    () => {
      const el = document.querySelector('#ctlNext, .submitbtn, #submit_button');
      if (!el) return false;
      el.click();
      return true;
    }
    """

    /// 读取提交结果：返回 {code, joinid}
    static let readResult = """
    () => {
      const url = location.href;
      const body = document.body ? (document.body.innerText || '') : '';
      let joinid = '';
      const jm = url.match(/join(?:activity|id)=([0-9]+)/);
      if (jm) joinid = jm[1];
      if (!joinid) {
        const bm = body.match(/join(?:activity|id)=([0-9]+)/);
        if (bm) joinid = bm[1];
      }
      const cm = body.match(/(?:^|\\s)([0-9]{1,2})〒/);
      const code = cm ? cm[1] : '';
      const done = /提交|感謝|感谢|成功/.test(body);
      return { code: code, joinid: joinid, done: done, url: url };
    }
    """
}
