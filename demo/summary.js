// Turns Playwright's JSON results into a Markdown table for the GitHub Actions summary.
const r = require(require('path').resolve(process.argv[2] || 'test-results/results.json'));
const rows = [];
(function walk(s, pre) {
  for (const sp of s.specs || []) for (const t of sp.tests) {
    const res = t.results[t.results.length - 1] || {}, st = t.status === 'expected' ? '✅ passed' : t.status === 'skipped' ? '⏭ skipped' : t.status === 'flaky' ? '⚠️ flaky' : '❌ failed';
    rows.push(`| ${t.projectName} | ${(pre ? pre + ' › ' : '') + sp.title} | ${st} | ${((res.duration || 0) / 1000).toFixed(1)} s |`);
  }
  for (const c of s.suites || []) walk(c, s.title && !/\.js$/.test(s.title) ? (pre ? pre + ' › ' : '') + s.title : pre);
})({ suites: r.suites }, '');
const st = r.stats || {};
console.log(`## Tripoli Points — offline demo tests\n\n${st.expected || 0} passed · ${st.unexpected || 0} failed · ${st.flaky || 0} flaky · ${st.skipped || 0} skipped\n`);
console.log('| Browser / width | Test | Result | Time |\n| --- | --- | --- | --- |\n' + rows.sort().join('\n'));
