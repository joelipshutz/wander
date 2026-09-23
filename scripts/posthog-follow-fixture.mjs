// Execute the production aggregation against synthetic SQL rows, never captured events.
import assert from 'node:assert/strict';
import { firstDayFollowSQL } from './posthog-product-dashboard.mjs';

if (process.env.WANDER_POSTHOG_PROJECT_ID !== '557259') throw new Error('Expected Astir project 557259');
const key = process.env.WANDER_POSTHOG_PERSONAL_API_KEY;
if (!key) throw new Error('Missing WANDER_POSTHOG_PERSONAL_API_KEY');
async function api(path, method = 'GET', body) {
  const response = await fetch(`https://us.posthog.com/api/projects/557259/${path}`, {
    method,
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!response.ok) throw new Error(`PostHog ${method} ${response.status}`);
  return response.json();
}
const production = firstDayFollowSQL();
const aggregation = production.slice(production.indexOf('), observed as ('));
const sql = `with cohort as (
  select 'multiple' as person_id, toDateTime('2026-09-18 12:00:00') as started_at
  union all select 'zero', toDateTime('2026-09-18 12:00:00')
  union all select 'zero_only', toDateTime('2026-09-17 12:00:00')
  union all select 'exactly_mature', toDateTime('2026-09-19 12:00:00')
  union all select 'not_yet_mature', toDateTime('2026-09-19 13:00:00')
  union all select 'young', toDateTime('2026-09-20 01:00:00')
), follow_events as (
  select 'multiple' as person_id, toDateTime('2026-09-18 11:59:59') as timestamp
  union all select 'multiple', toDateTime('2026-09-18 12:00:00')
  union all select 'multiple', toDateTime('2026-09-19 11:59:59')
  union all select 'multiple', toDateTime('2026-09-19 12:00:00')
  union all select 'multiple', toDateTime('2026-09-19 12:00:01')
  union all select 'exactly_mature', toDateTime('2026-09-19 12:01:00')
  union all select 'not_yet_mature', toDateTime('2026-09-19 14:00:00')
  union all select 'not_yet_mature', toDateTime('2026-09-19 15:00:00')
  union all select 'young', toDateTime('2026-09-20 02:00:00')
${aggregation}`.replaceAll('now()', "toDateTime('2026-09-20 12:00:00')");
let id;
try {
  id = (await api('insights/', 'POST', {
    name: 'REC-581 temporary first-day follow arithmetic validation',
    query: { kind: 'HogQLQuery', query: sql }, saved: false, tags: ['recme:validation-only'],
  })).id;
  const result = await api(`insights/${id}/?refresh=force_blocking`);
  assert.ok(!result.error && Array.isArray(result.result), 'Fixture must execute');
  const data = result.result.map(row => Object.fromEntries(result.columns.map((column, i) => [column, row[i]])));
  const row = day => data.find(item => item.cohort_day.startsWith(day));
  const pick = day => {
    const r = row(day);
    return ['cohort_users', 'eligible_users', 'pending_users', 'users_who_followed', 'first_day_follows', 'follow_rate_percent', 'follows_per_user'].map(key => r[key]);
  };
  assert.equal(data.length, 4);
  assert.deepEqual(pick('2026-09-17'), [1, 1, 0, 0, 0, 0, 0], 'A mature zero-follow user is measured as zero');
  assert.deepEqual(pick('2026-09-18'), [2, 2, 0, 1, 2, 50, 1], 'Include start, exclude end, count actions and keep zero-follow denominator');
  assert.deepEqual(pick('2026-09-19'), [2, 1, 1, 1, 1, 100, 1], '24h maturity is inclusive; pending users contribute no actions');
  assert.deepEqual(pick('2026-09-20'), [1, 0, 1, 0, null, null, null], 'Immature observed follows yield null metrics, not zero');
  console.log(JSON.stringify({ result: 'PASS', scenarios: 4, rows: data }, null, 2));
} finally {
  if (id) {
    await api(`insights/${id}/`, 'PATCH', { deleted: true });
    console.log('Temporary validation insight soft-deleted. No events ingested.');
  }
}

// Completed onboarding is the denominator even when an action occurs first.
const { activationSQL } = await import('./posthog-product-dashboard.mjs');
const activationAggregation = activationSQL().slice(activationSQL().indexOf('), observed as ('));
const activationFixture = `with cohort as (
  select 'follow_before' as person_id, toDateTime('2026-09-19 12:00:00') as completed_at
  union all select 'several_actions', toDateTime('2026-09-19 12:00:00')
  union all select 'outside_window', toDateTime('2026-09-19 12:00:00')
), actions as (
  select 'follow_before' as person_id, toDateTime('2026-09-05 12:00:00') as timestamp
  union all select 'several_actions', toDateTime('2026-09-19 13:00:00')
  union all select 'several_actions', toDateTime('2026-10-03 12:00:00')
  union all select 'outside_window', toDateTime('2026-09-05 11:59:59')
  union all select 'outside_window', toDateTime('2026-10-03 12:00:01')
  union all select 'never_onboarded', toDateTime('2026-09-19 13:00:00')
${activationAggregation}`;
id = undefined;
try {
  id = (await api('insights/', 'POST', {
    name: 'REC-581 temporary activation denominator validation',
    query: { kind: 'HogQLQuery', query: activationFixture }, saved: false, tags: ['recme:validation-only'],
  })).id;
  const result = await api(`insights/${id}/?refresh=force_blocking`);
  assert.ok(!result.error && Array.isArray(result.result), 'Activation fixture must execute');
  assert.deepEqual(result.result, [
    ['Completed onboarding', 3, 100],
    ['Follow / Wanna / check-in (66.7%)', 2, 66.7],
  ], 'Exclude action-only users and out-of-window actions; count qualifying people once');
  console.log(JSON.stringify({ result: 'PASS', scope: 'Activation denominator, deduplication and 14-day boundaries', rows: result.result }));
} finally {
  if (id) {
    await api(`insights/${id}/`, 'PATCH', { deleted: true });
    console.log('Temporary activation insight soft-deleted. No events ingested.');
  }
}
