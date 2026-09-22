#!/usr/bin/env python3
"""Two real PostgreSQL connections, verbatim production mutation/lifecycle SQL.
Requires a disposable *local* PostgreSQL database and libpq; no hosted URL accepted.
The fixture deliberately narrows schema/metadata adapters, so this complements
full-schema rollback pgTAP and never substitutes for its authorization checks.
"""
import argparse, ctypes as c, json, re, threading, time, uuid
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument('--libpq',required=True)
parser.add_argument('--socket',required=True)
parser.add_argument('--port',type=int,required=True)
parser.add_argument('--report',required=True)
args=parser.parse_args()
assert args.socket.startswith('/private/tmp/astir-joint-races/'), 'Use the task-owned disposable local socket'
lib=c.CDLL(args.libpq)
for name,restype,argtypes in [
 ('PQconnectdb',c.c_void_p,[c.c_char_p]),('PQstatus',c.c_int,[c.c_void_p]),
 ('PQexec',c.c_void_p,[c.c_void_p,c.c_char_p]),('PQresultStatus',c.c_int,[c.c_void_p]),
 ('PQresultErrorMessage',c.c_char_p,[c.c_void_p]),('PQresultErrorField',c.c_char_p,[c.c_void_p,c.c_int]),
 ('PQntuples',c.c_int,[c.c_void_p]),('PQnfields',c.c_int,[c.c_void_p]),
 ('PQgetvalue',c.c_char_p,[c.c_void_p,c.c_int,c.c_int]),('PQclear',None,[c.c_void_p]),
 ('PQfinish',None,[c.c_void_p]),('PQbackendPID',c.c_int,[c.c_void_p])]:
 f=getattr(lib,name);f.restype=restype;f.argtypes=argtypes
class DatabaseError(Exception):
 def __init__(self,code,message): self.code=code;super().__init__(message)
database="postgres"
class DB:
 def __init__(self):
  self.conn=lib.PQconnectdb(f'host={args.socket} port={args.port} user=joint_test dbname={database}'.encode())
  assert lib.PQstatus(self.conn)==0,'Local database connection failed'
  self.pid=lib.PQbackendPID(self.conn)
  self.query("set statement_timeout='12s';set lock_timeout='10s';set deadlock_timeout='100ms'")
 def query(self,sql):
  r=lib.PQexec(self.conn,sql.encode())
  try:
   if lib.PQresultStatus(r) not in (1,2):
    code=lib.PQresultErrorField(r,67)
    raise DatabaseError(code.decode() if code else '',lib.PQresultErrorMessage(r).decode())
   return [[lib.PQgetvalue(r,i,j).decode() for j in range(lib.PQnfields(r))] for i in range(lib.PQntuples(r))]
  finally:lib.PQclear(r)
 def close(self):lib.PQfinish(self.conn)
root=Path(__file__).resolve().parents[1];control=DB()
database='joint_race_'+uuid.uuid4().hex
control.query(f'create database {database}');admin=DB()
# Refuse reuse: a previous database must be explicitly removed/reinitialized.
assert admin.query("select count(*) from pg_namespace where nspname='app'")[0][0]=='0','Fixture database is not empty'
admin.query((root/'supabase/tests/joint_check_in_race_fixture.sql').read_text())
mutation=(root/'supabase/migrations/20260921221000_joint_check_in_mutations.sql').read_text()
needed={'app.lock_joint_check_in_request','app.joint_check_in_payload_hash','app.lock_active_joint_check_in',
 'app.joint_check_in_mutation_result','app.reconcile_joint_check_in_invitees','app.save_joint_check_in_contribution',
 'app.respond_to_joint_check_in','public.accept_joint_check_in','public.set_joint_check_in_invitees',
 'app.close_joint_check_in','public.leave_joint_check_in'}
loaded=[]
for match in re.finditer(r'create function\s+(\S+?)\(.*?\$\$;',mutation,re.S):
 if match[1] in needed:admin.query(match[0]);loaded.append(match[1])
assert set(loaded)==needed, 'A production function was not loaded'
lifecycle=(root/'supabase/migrations/20260921222000_joint_check_in_lifecycle_guards.sql').read_text()
admin.query(lifecycle.split('-- Preserve the deployed')[0].removeprefix('begin;'))
def load_functions(path,names):
 text=(root/path).read_text();found=set()
 for match in re.finditer(r'create(?: or replace)? function\s+(\S+?)\(.*?\$\$;',text,re.S):
  if match[1] in names:admin.query(match[0]);found.add(match[1]);loaded.append(match[1])
 assert found==names, f'Missing functions: {names-found}'
load_functions('supabase/migrations/20260602131500_m3_foundation.sql',{'app.can_read_user_place'})
load_functions('supabase/migrations/20260921223000_joint_check_in_projections.sql',{
 'app.readable_joint_check_in_members','app.visible_joint_group_for_visit','app.resolve_activity_v2','app.joint_profile_json'})
load_functions('supabase/migrations/20260810155601_activity_engagement.sql',{'app.activity_engagement_json'})
load_functions('supabase/migrations/20260921224000_joint_check_in_engagement.sql',{
 'app.lock_activity_v2','app.mark_joint_personal_engagement','app.activity_comment_json',
 'public.add_activity_comment_v2','public.set_activity_like_v2','public.delete_own_activity_comment'})
admin.query("create trigger activity_comments_00_joint_identity before insert on activity_comments for each row execute function app.mark_joint_personal_engagement();create trigger activity_likes_00_joint_identity before insert on activity_likes for each row execute function app.mark_joint_personal_engagement()")
G='e5660000-0000-0000-0000-000000000001';PLACE='e5660000-0000-0000-0000-000000000002'
SOURCE='e5660000-0000-0000-0000-000000000003';PARENT='e5660000-0000-0000-0000-000000000004'
MEMBER='e5660000-0000-0000-0000-000000000005';VISIT='e5660000-0000-0000-0000-000000000006'
CHILD='e5660000-0000-0000-0000-000000000007'
def seed(count=1):
 admin.query('truncate activity_comments,activity_likes,notification_events,joint_check_in_operations,feed_events,shared_visit_participants,shared_visit_groups,place_visits,user_places,places,profiles,follows,blocks cascade')
 admin.query("insert into profiles(id) values ('owner'),"+','.join(f"('friend{i}')" for i in range(10)))
 admin.query("insert into follows select 'owner',id from profiles where id<>'owner';insert into follows select id,'owner' from profiles where id<>'owner'")
 admin.query(f"insert into places(id) values('{PLACE}');insert into user_places(id,user_id,place_id) values('{PARENT}','owner','{PLACE}');insert into place_visits(id,user_place_id,visited_at) values('{SOURCE}','{PARENT}','2026-09-20T12:00:00Z');insert into shared_visit_groups(id,source_visit_id,owner_user_id,place_id) values('{G}','{SOURCE}','owner','{PLACE}');insert into feed_events(shared_visit_group_id) values('{G}');insert into shared_visit_participants(group_id,user_id,status,visit_id) values('{G}','owner','owner','{SOURCE}')")
 for i in range(count):
  member=MEMBER if i==0 else str(uuid.uuid4())
  admin.query(f"insert into shared_visit_participants(id,group_id,user_id,status,invitation_snapshot) values('{member}','{G}','friend{i}','pending','{{}}')")
def accept(op=None,visit=VISIT,generation=1):
 return f"select public.accept_joint_check_in('{MEMBER}',{generation},{generation},'{op or uuid.uuid4()}',1,'{CHILD}','{visit}','{{\"visibility\":\"followers\"}}','{{\"note\":\"Own fictional note\"}}')"
def set_people(people,rev=1):
 ids='array['+','.join("'"+p+"'" for p in people)+']::text[]'
 return f"select public.set_joint_check_in_invitees('{G}',{rev},{ids},'{uuid.uuid4()}')"
def wait_lock(db):
 deadline=time.monotonic()+5
 while time.monotonic()<deadline:
  rows=admin.query(f"select wait_event_type from pg_stat_activity where pid={db.pid}")
  if rows and rows[0][0]=='Lock':return
  time.sleep(.01)
 raise AssertionError(f'Connection {db.pid} never waited for a real database lock')
def race(first,second,first_user='friend0',second_user='friend0'):
 blocker=DB();left=DB();right=DB();out={}
 blocker.query(f"begin;select id from shared_visit_groups where id='{G}' for update")
 def run(label,db,user,sql):
  try:
   db.query(f"begin;select set_config('test.user_id','{user}',true)")
   rows=db.query(sql);db.query('commit');out[label]={'rows':rows}
  except DatabaseError as e:db.query('rollback');out[label]={'error':str(e).splitlines()[0],'code':e.code}
  finally:db.close()
 a=threading.Thread(target=run,args=('first',left,first_user,first));b=threading.Thread(target=run,args=('second',right,second_user,second))
 a.start();wait_lock(left);b.start();wait_lock(right);blocker.query('commit');blocker.close()
 a.join(15);b.join(15);assert not a.is_alive() and not b.is_alive()
 return out
def count(sql):return int(admin.query(sql)[0][0])
def success(out,which='first'):assert 'rows' in out[which],out
report={'scope':'Two-connection production mutation/lifecycle lock tests on narrow local fixture; not full-schema/RLS tests','functions_loaded':loaded,'cases':[]}
def record(name,out):
 report['cases'].append({'case':name,'passed':True,'results':out});Path(args.report).write_text(json.dumps(report,indent=2));print(name+': passed',flush=True)
seed();op=str(uuid.uuid4());out=race(accept(op),accept(op));success(out);success(out,'second')
assert out['first']['rows']==out['second']['rows'];assert count(f"select count(*) from place_visits where id='{VISIT}'")==1
assert count('select count(*) from joint_check_in_operations')==1;record('Same acceptance request on two devices creates one visit and receipt',out)
seed();out=race(accept(),accept(visit=str(uuid.uuid4())));success(out);assert 'invitation_unavailable' in out['second']['error']
assert count('select count(*) from place_visits')==2;record('Different acceptance requests cannot duplicate one membership',out)
seed();out=race(set_people([]),accept(),'owner','friend0');success(out);assert 'invitation_unavailable' in out['second']['error'];assert count('select count(*) from place_visits')==1;record('Removal wins acceptance race without creating a visit',out)
seed();out=race(accept(),set_people([]),'friend0','owner');success(out);assert 'stale_joint_check_in_revision' in out['second']['error']
admin.query("select set_config('test.user_id','owner',false)");admin.query(set_people([],2));assert count(f"select count(*) from place_visits where id='{VISIT}'")==1
assert admin.query(f"select status,visit_id is null from shared_visit_participants where id='{MEMBER}'")[0]==['removed','t'];record('Acceptance wins removal race; fresh removal retains the owned visit',out)
seed(9);out=race(set_people([f'friend{i}' for i in range(9)]),set_people([f'friend{i}' for i in range(1,10)]),'owner','owner');success(out);assert 'stale_joint_check_in_revision' in out['second']['error'];assert count("select count(*) from shared_visit_participants where status in ('owner','pending','accepted')")==10;record('Concurrent exact-set updates preserve ten-seat capacity and reject stale revision',out)
seed();out=race(f"update user_places set visibility='self' where id='{PARENT}'",accept(),'owner','friend0');success(out);assert 'joint_check_in_closed' in out['second']['error'];assert count('select count(*) from place_visits')==1;record('Source privacy wins acceptance race and permanently closes the group',out)
seed();out=race(accept(),f"update user_places set visibility='self' where id='{PARENT}'",'friend0','owner');success(out);success(out,'second');assert count('select count(*) from place_visits')==2;assert count("select count(*) from shared_visit_participants where status in ('owner','accepted','pending')")==0;record('Acceptance then source privacy preserves personal visits with no live membership',out)
def canonical():return admin.query(f"select id from feed_events where shared_visit_group_id='{G}'")[0][0]
def comment(event,request=None):return f"select public.add_activity_comment_v2('{event}','Fictional shared comment','{request or uuid.uuid4()}',1)"
seed();event=canonical();request=str(uuid.uuid4());out=race(comment(event,request),comment(event,request));success(out);success(out,'second')
assert out['first']['rows']==out['second']['rows'];assert count('select count(*) from activity_comments')==1;record('Concurrent comment retries create one shared comment and receipt',out)
seed();event=canonical();out=race(f"update user_places set visibility='self' where id='{PARENT}'",comment(event),'owner','friend0');success(out);assert 'activity_not_visible' in out['second']['error'];assert count('select count(*) from activity_comments')==0;record('Closure wins comment race and no comment is written',out)
seed();event=canonical();out=race(comment(event),f"update user_places set visibility='self' where id='{PARENT}'",'friend0','owner');success(out);success(out,'second')
admin.query("select set_config('test.user_id','friend0',false)")
comment_id=admin.query('select id from activity_comments')[0][0]
removed=json.loads(admin.query(f"select public.delete_own_activity_comment('{comment_id}')")[0][0]);assert removed['is_available'] is False
record('Comment wins closure race; its author can delete without regaining thread access',out)
seed();event=canonical();out=race(f"select public.set_activity_like_v2('{event}',true)",f"select public.set_activity_like_v2('{event}',true)");success(out);success(out,'second');assert count('select count(*) from activity_likes')==1;record('Concurrent like-set requests retain one like',out)
seed();event=canonical();out=race(f"update user_places set visibility='self' where id='{PARENT}'",f"select public.set_activity_like_v2('{event}',true)",'owner','friend0');success(out);assert 'activity_not_visible' in out['second']['error'];assert count('select count(*) from activity_likes')==0;record('Closure wins like race without a late write',out)
def prepare_rejoin():
 seed();admin.query("select set_config('test.user_id','friend0',false)");admin.query(accept())
 admin.query("select set_config('test.user_id','owner',false)");admin.query(set_people([],2));admin.query(set_people(['friend0'],3))
 return admin.query(f"insert into feed_events(visit_id) values('{VISIT}') returning id")[0][0]
event=prepare_rejoin();out=race(comment(event),accept(generation=2));success(out);success(out,'second')
assert admin.query(f"select standalone_engagement_started_at is not null from feed_events where id='{event}'")[0][0]=='t'
admin.query("select set_config('test.user_id','friend0',false)");assert admin.query(f"select app.resolve_activity_v2('friend0','{event}')")[0][0]==event
assert count('select count(*) from place_visits')==2;record('Personal comment wins rejoin race and permanently pins the personal thread',out)
event=prepare_rejoin();out=race(accept(generation=2),comment(event));success(out);assert 'activity_context_changed' in out['second']['error'];assert count('select count(*) from activity_comments')==0;record('Rejoin wins personal comment race; stale draft is not retargeted',out)
report['passed']=len(report['cases']);Path(args.report).write_text(json.dumps(report,indent=2));admin.close()
control.query(f'drop database {database}');control.close()
