import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import pg from "pg";

const Pool = pg.Pool;
const ACK = "YES_I_UNDERSTAND_THIS_IS_A_DISPOSABLE_ST8_TEST_DATABASE";
const PROD = "kxcuvagipqiqisowtgys";
const BASE_STAGING = "liiowoclsddlywabvmcg";
const required = name => {
  const value = process.env[name]?.trim();
  if (!value) throw new Error("Missing environment variable: " + name);
  return value;
};
if (required("ST8_TEST_ALLOW_DISPOSABLE_DB") !== ACK) throw new Error("Disposable DB acknowledgement missing.");
const projectRef = required("ST8_TEST_PROJECT_REF");
if (projectRef === PROD || projectRef === BASE_STAGING) throw new Error("Production/base staging target refused.");
const connectionString = required("ST8_TEST_DATABASE_URL");
const parsedUrl = new URL(connectionString);
const local = ["localhost", "127.0.0.1", "::1"].includes(parsedUrl.hostname);
if (!local && parsedUrl.hostname !== "db." + projectRef + ".supabase.co") {
  throw new Error("Only localhost or exact direct host db.<project-ref>.supabase.co is accepted.");
}
const workers = Number(process.env.ST8_TEST_WORKERS || 20);
if (!Number.isInteger(workers) || workers < 2 || workers > 100) throw new Error("ST8_TEST_WORKERS must be 2..100.");
const pool = new Pool({
  connectionString, max: workers, connectionTimeoutMillis: 10000,
  idleTimeoutMillis: 10000, statement_timeout: 30000, query_timeout: 35000,
  application_name: "asix-st8-v090-concurrency-test",
  ssl: process.env.ST8_TEST_SSL === "disable" ? false : { rejectUnauthorized: true }
});
const runId = new Date().toISOString().replace(/[-:.TZ]/g, "") + "-" + crypto.randomBytes(4).toString("hex");
const prefix = "asixv090_" + runId;
const results = [];
const digest = value => crypto.createHash("sha256").update(value).digest();
const WALLET_SQL = [
  "select public.st8_process_wallet_callback(",
  "$1::text,$2::text,$3::text,$4::text,$5::text,$6::text,$7::text,",
  "$8::bigint,$9::bytea,$10::text,$11::text,$12::text,$13::text,$14::bytea,$15::jsonb",
  ") as result"
].join(" ");
const FUNDING_SQL = [
  "select public.st8_credit_wallet_from_trusted_source(",
  "$1::uuid,$2::bigint,$3::text,$4::text,$5::text,$6::jsonb",
  ") as result"
].join(" ");

function assert(ok, message) { if (!ok) throw new Error(message); }
async function withService(fn) {
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query("set local role service_role");
    await client.query("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({ role: "service_role" })]);
    const result = await fn(client);
    await client.query("commit");
    return result;
  } catch (error) {
    try { await client.query("rollback"); } catch {}
    throw error;
  } finally { client.release(); }
}
async function wallet(ctx, x) {
  const values = [
    x.action, x.tx || null, x.cancel || null, x.ref || null,
    ctx.player, ctx.site, x.currency === undefined ? "GEL" : x.currency,
    x.amount === undefined ? null : String(x.amount), ctx.walletHash, null,
    ctx.game, ctx.developer, x.kind || null,
    x.hash || digest(x.action + ":" + (x.tx || x.cancel) + ":" + (x.amount || "")),
    JSON.stringify({ runId, test: x.test || "case" })
  ];
  return withService(async c => (await c.query(WALLET_SQL, values)).rows[0].result);
}
async function funding(ctx, amount, key) {
  return withService(async c => (await c.query(FUNDING_SQL, [
    ctx.user, String(amount), key, "payment_deposit", runId + ":" + key, JSON.stringify({ runId })
  ])).rows[0].result);
}
async function fixture(name, opts = {}) {
  const user = crypto.randomUUID();
  const suffix = crypto.randomBytes(7).toString("hex");
  const player = "st8test_" + suffix;
  const site = "test_site_" + runId;
  const game = "test_game_" + runId;
  const developer = "ASIX_TEST_DEV";
  const walletHash = digest("wallet:" + user);
  await pool.query(
    "insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,is_anonymous,created_at,updated_at) " +
    "values($1::uuid,'authenticated','authenticated',$2,'',now(),'{\"provider\":\"email\",\"providers\":[\"email\"]}'::jsonb,'{}'::jsonb,false,now(),now())",
    [user, prefix + "." + suffix + "@st8.invalid"]
  );
  await pool.query(
    "insert into provider_internal.st8_sites(site_id,enabled,currency) values($1,true,'GEL') on conflict(site_id) do update set enabled=true",
    [site]
  );
  await pool.query(
    "insert into provider_internal.st8_games(game_code,developer_code,enabled,provider_enabled,blocked_countries,allowed_jurisdictions,min_age_years,min_bet_tetri,max_bet_tetri,max_payout_tetri) " +
    "values($1,$2,true,true,'{}'::text[],array['GE']::text[],18,1,10000000,100000000) on conflict(game_code) do update set enabled=true,provider_enabled=true",
    [game, developer]
  );
  await pool.query(
    "insert into provider_internal.st8_player_mappings(st8_player_id,user_id,status,jurisdiction,default_currency,reg_country,birth_date,age_verified,real_money_eligible,self_excluded,reg_date,daily_wager_limit_tetri,daily_wager_timezone,max_single_bet_tetri) " +
    "values($1,$2::uuid,'ACTIVE','GE','GEL','GE','1990-01-01',true,true,false,current_date,$3::bigint,'UTC',$4::bigint)",
    [player,user,String(opts.limit || 100000),String(opts.maxSingle || 10000)]
  );
  await pool.query(
    "insert into provider_internal.st8_wallet_sessions(token_hash,user_id,st8_player_id,game_code,site_id,currency,status) " +
    "values($1::bytea,$2::uuid,$3,$4,$5,'GEL','ACTIVE')",
    [walletHash,user,player,game,site]
  );
  const ctx = { user, player, site, game, developer, walletHash };
  if ((opts.balance || 0) > 0) {
    const result = await funding(ctx, opts.balance, "seed:" + prefix + ":" + name);
    assert(result.ok && !result.duplicate, "Failed to seed test wallet for " + name);
  }
  return ctx;
}
async function snapshot(ctx) {
  const sql = "select coalesce((select balance_tetri from provider_internal.st8_wallet_accounts where user_id=$1::uuid),0)::bigint as balance," +
    "coalesce((select outstanding_tetri from provider_internal.st8_player_debts where user_id=$1::uuid),0)::bigint as debt," +
    "(select count(*)::bigint from provider_internal.st8_wallet_ledger where user_id=$1::uuid) as ledger_count," +
    "(select count(*)::bigint from provider_internal.st8_transactions where user_id=$1::uuid) as tx_count";
  return (await pool.query(sql,[ctx.user])).rows[0];
}
async function ledger(ctx) {
  return (await pool.query(
    "select id,entry_type,amount_tetri::text as amount,balance_after_tetri::text as after,idempotency_key " +
    "from provider_internal.st8_wallet_ledger where user_id=$1::uuid order by id",[ctx.user]
  )).rows;
}
async function txRows(ctx) {
  return (await pool.query(
    "select st8_transaction_id,cancel_id,state,action_kind from provider_internal.st8_transactions where user_id=$1::uuid order by id",
    [ctx.user]
  )).rows;
}
async function test(id, title, fn) {
  const start = Date.now();
  try {
    const evidence = await fn();
    results.push({ id, title, status: "PASS", duration_ms: Date.now() - start, evidence });
    process.stdout.write("PASS " + id + " " + title + "\n");
  } catch (e) {
    results.push({ id, title, status: "FAIL", duration_ms: Date.now() - start,
      error: { message: e.message, code: e.code || null } });
    process.stderr.write("FAIL " + id + " " + title + ": " + e.message + "\n");
  }
}
async function preflight() {
  const f = await pool.query(
    "select current_database() as db,current_setting('server_version_num')::int as version_num," +
    "to_regprocedure('public.st8_process_wallet_callback(text,text,text,text,text,text,text,bigint,bytea,text,text,text,text,bytea,jsonb)') is not null as callback_ok," +
    "to_regprocedure('public.st8_credit_wallet_from_trusted_source(uuid,bigint,text,text,text,jsonb)') is not null as funding_ok," +
    "has_function_privilege('service_role',to_regprocedure('public.st8_process_wallet_callback(text,text,text,text,text,text,text,bigint,bytea,text,text,text,text,bytea,jsonb)'),'EXECUTE') as service_callback_exec," +
    "has_function_privilege('anon',to_regprocedure('public.st8_process_wallet_callback(text,text,text,text,text,text,text,bigint,bytea,text,text,text,text,bytea,jsonb)'),'EXECUTE') as anon_callback_exec," +
    "has_function_privilege('authenticated',to_regprocedure('public.st8_process_wallet_callback(text,text,text,text,text,text,text,bigint,bytea,text,text,text,text,bytea,jsonb)'),'EXECUTE') as authenticated_callback_exec," +
    "has_function_privilege('service_role',to_regprocedure('public.st8_credit_wallet_from_trusted_source(uuid,bigint,text,text,text,jsonb)'),'EXECUTE') as service_funding_exec," +
    "has_function_privilege('anon',to_regprocedure('public.st8_credit_wallet_from_trusted_source(uuid,bigint,text,text,text,jsonb)'),'EXECUTE') as anon_funding_exec," +
    "has_function_privilege('authenticated',to_regprocedure('public.st8_credit_wallet_from_trusted_source(uuid,bigint,text,text,text,jsonb)'),'EXECUTE') as authenticated_funding_exec"
  );
  const info = f.rows[0];
  assert(info.version_num >= 170000 && info.version_num < 180000, "PostgreSQL 17.x required.");
  assert(info.callback_ok && info.funding_ok, "ST8 RPC functions missing.");
  assert(info.service_callback_exec && info.service_funding_exec, "service_role must have EXECUTE on both wallet RPCs.");
  assert(!info.anon_callback_exec && !info.authenticated_callback_exec &&
    !info.anon_funding_exec && !info.authenticated_funding_exec,
    "Wallet RPC EXECUTE must be denied to anon and authenticated roles.");
  const p = (await pool.query(
    "select count(*)::int as tables,count(*) filter(where c.relrowsecurity)::int as rls," +
    "count(*) filter(where c.relforcerowsecurity)::int as force_rls," +
    "has_schema_privilege('anon','provider_internal','USAGE') as anon_usage," +
    "has_schema_privilege('authenticated','provider_internal','USAGE') as auth_usage," +
    "has_schema_privilege('service_role','provider_internal','USAGE') as service_usage " +
    "from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='provider_internal' and c.relkind='r'"
  )).rows[0];
  assert(p.tables === 14 && p.rls === 14 && p.force_rls === 14, "Expected 14/14 private tables with RLS + FORCE RLS.");
  assert(!p.anon_usage && !p.auth_usage && !p.service_usage, "provider_internal schema USAGE must be denied to API roles.");
  const empty = (await pool.query(
    "select (select count(*) from provider_internal.st8_sites)+" +
    "(select count(*) from provider_internal.st8_games)+" +
    "(select count(*) from provider_internal.st8_player_mappings)+" +
    "(select count(*) from provider_internal.st8_launch_tokens)+" +
    "(select count(*) from provider_internal.st8_wallet_sessions)+" +
    "(select count(*) from provider_internal.st8_wallet_accounts)+" +
    "(select count(*) from provider_internal.st8_wallet_ledger)+" +
    "(select count(*) from provider_internal.st8_audit_events)+" +
    "(select count(*) from provider_internal.st8_player_debts)+" +
    "(select count(*) from provider_internal.st8_debt_events)+" +
    "(select count(*) from provider_internal.st8_transactions)+" +
    "(select count(*) from provider_internal.st8_reconciliation_runs)+" +
    "(select count(*) from provider_internal.st8_reconciliation_issues)+" +
    "(select count(*) from provider_internal.st8_alert_outbox) as rows"
  )).rows[0];
  assert(Number(empty.rows) === 0, "ST8 schema has existing rows; refusing to seed.");
  process.stdout.write("Preflight PASS: PG17, 14/14 RLS+FORCE RLS, zero ST8 rows, no API-role schema USAGE\n");
  return info;
}

async function main() {
  const info = await preflight();
  process.stdout.write("Disposable project " + projectRef + "; " + info.db + "; workers=" + workers + "\n");

  await test("C01","identical debit replay",async()=>{
    const c=await fixture("C01",{balance:1000});
    const x={action:"debit",tx:prefix+":C01",amount:100,kind:"debit",hash:digest("C01:same")};
    const [a,b]=await Promise.all([wallet(c,x),wallet(c,x)]);
    const s=await snapshot(c), l=(await ledger(c)).filter(r=>r.idempotency_key==="st8:"+x.tx);
    assert(a.status==="ok"&&b.status==="ok"&&[a,b].filter(r=>r.duplicate).length===1&&Number(s.balance)===900&&l.length===1,"C01 invariant failed");
    return {responses:[a,b],snapshot:s,ledger:l};
  });

  await test("C02","same transaction ID conflicting hash",async()=>{
    const c=await fixture("C02",{balance:1000}), id=prefix+":C02";
    const r=await Promise.allSettled([
      wallet(c,{action:"debit",tx:id,amount:100,kind:"debit",hash:digest("C02:a")}),
      wallet(c,{action:"debit",tx:id,amount:200,kind:"debit",hash:digest("C02:b")})
    ]);
    const ok=r.filter(x=>x.status==="fulfilled"), bad=r.filter(x=>x.status==="rejected"),s=await snapshot(c);
    assert(ok.length===1&&bad.length===1&&bad[0].reason.code==="23505"&&/IDEMPOTENCY_CONFLICT/.test(bad[0].reason.message)&&[800,900].includes(Number(s.balance)),"C02 invariant failed");
    return {winner:ok[0].value,conflict:bad[0].reason.message,snapshot:s};
  });

  await test("C03","two 700-tetri debits against 1000 balance",async()=>{
    const c=await fixture("C03",{balance:1000});
    const r=await Promise.all(["a","b"].map(k=>wallet(c,{action:"debit",tx:prefix+":C03:"+k,amount:700,kind:"debit"})));
    const s=await snapshot(c),bets=(await ledger(c)).filter(x=>x.entry_type==="provider_bet");
    assert(r.filter(x=>x.status==="ok").length===1&&r.filter(x=>x.status==="not_enough_money").length===1&&Number(s.balance)===300&&bets.length===1,"C03 invariant failed");
    return {responses:r,snapshot:s,bets};
  });

  await test("C04","daily wager limit race",async()=>{
    const c=await fixture("C04",{balance:5000,limit:1000,maxSingle:900});
    const r=await Promise.all(["a","b"].map(k=>wallet(c,{action:"debit",tx:prefix+":C04:"+k,amount:700,kind:"debit"})));
    const s=await snapshot(c),bets=(await ledger(c)).filter(x=>x.entry_type==="provider_bet");
    assert(r.filter(x=>x.status==="ok").length===1&&r.filter(x=>x.status==="spending_limit").length===1&&Number(s.balance)===4300&&bets.length===1,"C04 invariant failed");
    return {responses:r,snapshot:s,bets};
  });

  await test("C05","debit versus cancel race",async()=>{
    const c=await fixture("C05",{balance:1000}),tx=prefix+":C05";
    const r=await Promise.all([
      wallet(c,{action:"debit",tx,amount:200,kind:"debit"}),
      wallet(c,{action:"cancel",cancel:prefix+":C05:cancel",ref:tx})
    ]);
    const s=await snapshot(c),t=await txRows(c);
    assert(Number(s.balance)===1000&&t.some(x=>x.cancel_id===prefix+":C05:cancel")&&t.some(x=>x.st8_transaction_id===tx),"C05 invariant failed");
    return {responses:r,snapshot:s,transactions:t};
  });

  await test("C06","duplicate cancel replay",async()=>{
    const c=await fixture("C06",{balance:1000}),tx=prefix+":C06",cancel=prefix+":C06:cancel";
    await wallet(c,{action:"debit",tx,amount:300,kind:"debit"});
    const x={action:"cancel",cancel,ref:tx,hash:digest("C06:same")};
    const r=await Promise.all([wallet(c,x),wallet(c,x)]);
    const s=await snapshot(c),refund=(await ledger(c)).filter(x=>x.idempotency_key==="st8:cancel:"+cancel);
    assert(Number(s.balance)===1000&&refund.length===1&&r.filter(x=>x.duplicate).length===1,"C06 invariant failed");
    return {responses:r,snapshot:s,refund};
  });

  await test("C07","cancel ID conflicting hash",async()=>{
    const c=await fixture("C07",{balance:1000}),tx=prefix+":C07",cancel=prefix+":C07:cancel";
    await wallet(c,{action:"debit",tx,amount:300,kind:"debit"});
    const r=await Promise.allSettled([
      wallet(c,{action:"cancel",cancel,ref:tx,hash:digest("C07:a")}),
      wallet(c,{action:"cancel",cancel,ref:tx,hash:digest("C07:b")})
    ]);
    const ok=r.filter(x=>x.status==="fulfilled"),bad=r.filter(x=>x.status==="rejected");
    const s=await snapshot(c),refund=(await ledger(c)).filter(x=>x.idempotency_key==="st8:cancel:"+cancel);
    assert(ok.length===1&&bad.length===1&&bad[0].reason.code==="23505"&&/IDEMPOTENCY_CONFLICT/.test(bad[0].reason.message)&&Number(s.balance)===1000&&refund.length===1,"C07 invariant failed");
    return {winner:ok[0].value,conflict:bad[0].reason.message,snapshot:s,refund};
  });

  await test("C08","payout reversal versus debit",async()=>{
    const c=await fixture("C08",{balance:0}),payout=prefix+":C08:payout";
    const paid=await wallet(c,{action:"payout",tx:payout,amount:700,kind:"credit"});
    const r=await Promise.all([
      wallet(c,{action:"debit",tx:prefix+":C08:debit",amount:500,kind:"debit"}),
      wallet(c,{action:"cancel",cancel:prefix+":C08:cancel",ref:payout})
    ]);
    const s=await snapshot(c);
    assert(paid.status==="ok"&&Number(s.balance)===0&&[0,500].includes(Number(s.debt))&&r[1].status==="ok","C08 invariant failed");
    return {paid,responses:r,snapshot:s};
  });

  await test("C09","trusted funding duplicate key",async()=>{
    const c=await fixture("C09",{balance:0}),key=prefix+":C09:fund";
    const r=await Promise.all([funding(c,500,key),funding(c,500,key)]);
    const s=await snapshot(c),l=(await ledger(c)).filter(x=>x.idempotency_key==="funding:"+key);
    assert(Number(s.balance)===500&&l.length===1&&r.filter(x=>x.duplicate).length===1,"C09 invariant failed");
    return {responses:r,snapshot:s,ledger:l};
  });

  await test("C10","trusted funding conflicting amount",async()=>{
    const c=await fixture("C10",{balance:0}),key=prefix+":C10:fund";
    const r=await Promise.allSettled([funding(c,500,key),funding(c,600,key)]);
    const ok=r.filter(x=>x.status==="fulfilled"),bad=r.filter(x=>x.status==="rejected");
    const s=await snapshot(c),l=(await ledger(c)).filter(x=>x.idempotency_key==="funding:"+key);
    assert(ok.length===1&&bad.length===1&&bad[0].reason.code==="23505"&&/IDEMPOTENCY_CONFLICT/.test(bad[0].reason.message)&&l.length===1&&[500,600].includes(Number(s.balance)),"C10 invariant failed");
    return {winner:ok[0].value,conflict:bad[0].reason.message,snapshot:s,ledger:l};
  });

  await test("C11","tombstone precedes late original",async()=>{
    const c=await fixture("C11",{balance:1000}),tx=prefix+":C11:late",cancel=prefix+":C11:cancel";
    const a=await wallet(c,{action:"cancel",cancel,ref:tx});
    const b=await wallet(c,{action:"debit",tx,amount:250,kind:"debit"});
    const s=await snapshot(c),t=await txRows(c),l=await ledger(c);
    assert(a.status==="transaction_not_found"&&b.status==="ok"&&Number(s.balance)===1000&&
      t.some(x=>x.st8_transaction_id===tx&&x.state==="CANCELLED_BEFORE_ORIGINAL")&&
      t.some(x=>x.cancel_id===cancel&&x.state==="APPLIED_TO_LATE_ORIGINAL")&&
      !l.some(x=>x.entry_type==="provider_bet"),"C11 invariant failed");
    return {tombstone:a,lateOriginal:b,snapshot:s,transactions:t};
  });

  await test("C12","20–100 distinct concurrent transaction IDs",async()=>{
    const c=await fixture("C12",{balance:10000,limit:100000,maxSingle:1000});
    const r=await Promise.all(Array.from({length:workers},(_,i)=>wallet(c,{
      action:"debit",tx:prefix+":C12:"+String(i).padStart(3,"0"),amount:10,kind:"debit"
    })));
    const s=await snapshot(c),l=await ledger(c),bets=l.filter(x=>x.entry_type==="provider_bet");
    assert(r.every(x=>x.status==="ok"&&!x.duplicate)&&bets.length===workers&&Number(s.balance)===10000-workers*10,"C12 count/balance invariant failed");
    let previous=10000;
    for(const row of bets){const after=Number(row.after);assert(after===previous-10,"Ledger balance chain broken at id "+row.id);previous=after;}
    assert(previous===Number(s.balance),"Final ledger/account balance mismatch.");
    return {workers,accepted:r.length,snapshot:s,betCount:bets.length,first:bets.slice(0,5),last:bets.slice(-5)};
  });

  const passed=results.filter(x=>x.status==="PASS").length,failed=results.length-passed;
  const report={schema:"asix-st8-v0.9.0-concurrency-report/v1",runId,createdAt:new Date().toISOString(),
    target:{projectRef,database:info.db,serverVersionNum:info.version_num},workers,total:results.length,passed,failed,
    status:failed===0?"PASS":"FAIL",note:"Disposable DB only. Keep synthetic data for evidence; delete the full disposable branch after report export.",results};
  const outDir=path.resolve(process.env.ST8_TEST_OUTPUT_DIR||"./concurrency-results");
  await fs.mkdir(outDir,{recursive:true});
  const out=path.join(outDir,runId+".json");
  await fs.writeFile(out,JSON.stringify(report,null,2)+"\n",{mode:0o600});
  process.stdout.write("\nResult "+passed+"/"+results.length+" PASS; "+failed+" FAIL\nEvidence: "+out+"\n");
  if(failed)process.exitCode=1;
}
try { await main(); }
catch(e){process.stderr.write("FATAL: "+(e.stack||e.message)+"\n");process.exitCode=2;}
finally { await pool.end(); }
