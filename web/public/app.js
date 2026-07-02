(() => {
  'use strict';
  const ils = new Intl.NumberFormat('he-IL', { style: 'currency', currency: 'ILS' });
  const $ = (id) => document.getElementById(id);
  let currentParams = null;

  function show(el, visible) { el.classList.toggle('hidden', !visible); }

  function setLoading() {
    show($('error-banner'), false);
    show($('results'), false);
    show($('loading'), true);
  }

  function showError(message) {
    show($('loading'), false);
    show($('results'), false);
    const banner = $('error-banner');
    banner.textContent = message;
    show(banner, true);
  }

  function render(data) {
    $('period-label').textContent =
      'תקופה: ' + data.period.from + ' עד ' + data.period.to + ' (' + data.period.months + ' חודשים)';
    $('card-vat').textContent = ils.format(data.totals.vat);
    $('card-mikdamot').textContent = ils.format(data.totals.mikdamot);
    $('card-bl').textContent = ils.format(data.totals.bituachLeumiEstimate);
    $('sum-gross').textContent = ils.format(data.totals.gross);
    $('sum-net').textContent = ils.format(data.totals.net);

    const tbody = $('invoice-table').querySelector('tbody');
    tbody.replaceChildren();
    for (const inv of data.invoices) {
      const tr = document.createElement('tr');
      const cells = [inv.date, inv.documentNumber, inv.customer,
                     ils.format(inv.gross), ils.format(inv.net), ils.format(inv.vat)];
      for (const value of cells) {
        const td = document.createElement('td');
        td.textContent = value ?? '';
        tr.appendChild(td);
      }
      tbody.appendChild(tr);
    }
    const empty = data.invoices.length === 0;
    show($('empty-msg'), empty);
    $('invoice-table').classList.toggle('hidden', empty);
    show($('loading'), false);
    show($('results'), true);
  }

  async function load(params) {
    currentParams = params;
    setLoading();
    try {
      const res = await fetch('/api/summary?' + new URLSearchParams(params));
      const body = await res.json();
      if (!res.ok) { showError(body.error || 'שגיאה לא ידועה'); return; }
      render(body);
    } catch {
      showError('השרת אינו זמין.');
    }
  }

  function pad(n) { return String(n).padStart(2, '0'); }
  function monthStr(d) { return d.getFullYear() + '-' + pad(d.getMonth() + 1); }
  function dateStr(d) { return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()); }

  $('btn-this-month').addEventListener('click', () => {
    const m = monthStr(new Date());
    $('month-input').value = m;
    load({ month: m });
  });

  $('btn-prev-month').addEventListener('click', () => {
    const d = new Date();
    d.setDate(1);
    d.setMonth(d.getMonth() - 1);
    const m = monthStr(d);
    $('month-input').value = m;
    load({ month: m });
  });

  $('btn-vat-period').addEventListener('click', () => {
    // Bi-monthly VAT periods: Jan-Feb, Mar-Apr, May-Jun, Jul-Aug, Sep-Oct, Nov-Dec
    const now = new Date();
    const startMonth = now.getMonth() - (now.getMonth() % 2);
    const from = new Date(now.getFullYear(), startMonth, 1);
    const to = new Date(now.getFullYear(), startMonth + 2, 0);
    load({ from: dateStr(from), to: dateStr(to) });
  });

  $('month-input').addEventListener('change', (e) => {
    if (e.target.value) load({ month: e.target.value });
  });

  $('btn-apply-range').addEventListener('click', () => {
    const from = $('from-input').value;
    const to = $('to-input').value;
    if (!from || !to) { showError('יש לבחור תאריך התחלה ותאריך סיום.'); return; }
    load({ from, to });
  });

  $('btn-csv').addEventListener('click', () => {
    if (currentParams) {
      window.location.href = '/api/summary/csv?' + new URLSearchParams(currentParams);
    }
  });

  let currentRatePercent = null;

  function showRate(percent) {
    currentRatePercent = percent;
    $('rate-value').textContent = percent + '%';
    show($('rate-editor'), false);
    show($('btn-rate-edit'), true);
  }

  async function loadRate() {
    try {
      const res = await fetch('/api/rates');
      const body = await res.json();
      if (res.ok) {
        showRate(Math.round(body.mikdamotRate * 1000) / 10);
      } else {
        showError(body.error || 'שגיאה בטעינת אחוז המקדמות');
      }
    } catch {
      /* server-unavailable already surfaced by the summary load */
    }
  }

  $('btn-rate-edit').addEventListener('click', () => {
    $('rate-input').value = currentRatePercent ?? '';
    show($('btn-rate-edit'), false);
    show($('rate-editor'), true);
  });

  $('btn-rate-cancel').addEventListener('click', () => showRate(currentRatePercent));

  $('btn-rate-save').addEventListener('click', async () => {
    const percent = parseFloat($('rate-input').value);
    if (Number.isNaN(percent) || percent < 0 || percent >= 100) {
      showError('אחוז מקדמות לא תקין.');
      return;
    }
    try {
      const res = await fetch('/api/rates', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ mikdamotRate: percent / 100 })
      });
      const body = await res.json();
      if (!res.ok) {
        showError(body.error || 'שמירת אחוז המקדמות נכשלה');
        showRate(currentRatePercent);
        return;
      }
      showRate(Math.round(body.mikdamotRate * 1000) / 10);
      if (currentParams) load(currentParams);
    } catch {
      showError('השרת אינו זמין.');
    }
  });

  loadRate();

  $('btn-this-month').click();
})();
