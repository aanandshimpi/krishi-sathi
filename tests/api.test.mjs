import {test, before, after} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {scryptSync} from 'node:crypto';
import {createApp,today,distanceKm} from '../server/app.mjs';
let app,base,provider,farmer,other,team,booking,admin;
const dir=mkdtempSync(join(tmpdir(),'krishi-tests-'));
before(async()=>{app=createApp({dbPath:join(dir,'test.sqlite')});app.db.prepare('INSERT INTO admins(name,phone,password,salt) VALUES(?,?,?,?)').run('KVK Test Admin','9333333333',scryptSync('Temporary-admin-123','test-salt',64).toString('hex'),'test-salt');await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));base=`http://127.0.0.1:${app.server.address().port}`;});
after(async()=>{await app.close();rmSync(dir,{recursive:true,force:true});});
async function api(path,{token,body,method}={}){const res=await fetch(base+path,{method:method||(body?'POST':'GET'),headers:{...(token?{Authorization:`Bearer ${token}`} :{}),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:res.status,data:await res.json()};}
const register=(phone,role)=>api('/api/auth/register',{body:{phone,password:'test-password-123',name:role==='farmer'?'Test Farmer':'Test Provider',age:35,address:'Solapur farm road',role}});
const request=(overrides={})=>({teamId:team.id,task:'Harvesting',date:today(),workers:3,address:'Test farm in Solapur',lat:17.65,lng:75.9,requestKey:crypto.randomUUID(),...overrides});
test('registration, sign-in, session and provider role restrictions',async()=>{
 provider=(await register('9000000001','provider')).data;farmer=(await register('9000000002','farmer')).data;other=(await register('9000000003','farmer')).data;
 assert.equal(provider.user.role,'provider');assert.equal((await register('9000000002','farmer')).status,409);
 assert.equal((await api('/api/auth/login',{body:{phone:'9000000002',password:'incorrect-password'}})).status,401);
 const login=await api('/api/auth/login',{body:{phone:'9000000002',password:'test-password-123'}});assert.equal(login.status,200);
 assert.equal((await api('/api/me')).status,401);assert.equal((await api('/api/me',{token:farmer.token})).data.user.name,'Test Farmer');
 assert.equal((await api('/api/provider/team',{token:farmer.token})).status,403);
 assert.equal((await api('/api/auth/register',{body:{phone:'9000000004',password:'short',name:'No',age:35,address:'Farm',role:'farmer'}})).status,400);
});
test('provider publishes real team; location search filters and preserves privacy',async()=>{
 const result=await api('/api/provider/team',{token:provider.token,method:'PUT',body:{name:'Local Team',place:'Solapur',crops:['Grape'],skills:['Harvesting','Pruning'],people:5,price:450,lat:17.65,lng:75.9,available:true}});assert.equal(result.status,200);team=result.data.team;
 const nearby=await api('/api/teams?lat=17.65&lng=75.9&radius=10&crop=Grape');assert.equal(nearby.data.teams.length,1);assert.equal(nearby.data.teams[0].distanceKm,0);assert.equal(nearby.data.teams[0].lat,undefined);assert.equal(nearby.data.teams[0].verified,false);
 assert.equal((await api('/api/teams?lat=19&lng=73&radius=10')).data.teams.length,0);assert.equal((await api('/api/teams?crop=Onion')).data.teams.length,0);
 assert.equal((await api('/api/teams?lat=200&lng=75')).status,400);assert.equal((await api('/api/teams?lat=17.65')).status,400);assert.equal((await api('/api/teams?lat=&lng=75')).status,400);assert.ok(distanceKm(17.65,75.9,17.66,75.9)>1);
});
test('database booking, idempotent retries, provider inbox, owner-only access and server pricing',async()=>{
 const body=request({price:1,total:1});let res=await api('/api/bookings',{token:farmer.token,body});assert.equal(res.status,201);booking=res.data.booking;assert.equal(booking.total,1350);assert.equal(booking.status,'pending');assert.equal(booking.providerLocation,null);assert.equal((await api(`/api/bookings/${booking.id}/location-sharing`,{token:provider.token,method:'PATCH',body:{enabled:true}})).status,409);
 const retry=await api('/api/bookings',{token:farmer.token,body});assert.equal(retry.status,200);assert.equal(retry.data.booking.id,booking.id);
 assert.equal((await api('/api/bookings',{token:provider.token})).data.bookings[0].farmerPhone,'9000000002');assert.equal((await api('/api/bookings',{token:other.token})).data.bookings.length,0);
 assert.equal((await api(`/api/bookings/${booking.id}/status`,{token:other.token,method:'PATCH',body:{status:'cancelled'}})).status,404);
 assert.equal((await api('/api/bookings',{token:provider.token,body:request()})).status,403);
 assert.equal((await api('/api/bookings',{token:farmer.token,body:request({date:'2020-01-01'})})).status,400);
 assert.equal((await api('/api/bookings',{token:farmer.token,body:request({workers:6})})).status,400);
 assert.equal((await api('/api/bookings',{token:farmer.token,body:request({task:'Unknown'})})).status,400);
});
test('acceptance reserves capacity, prevents overbooking and cancellation frees workers',async()=>{
 const second=(await api('/api/bookings',{token:other.token,body:request()})).data.booking;
 const accepted=await api(`/api/bookings/${booking.id}/status`,{token:provider.token,method:'PATCH',body:{status:'accepted'}});assert.equal(accepted.status,200);
 assert.equal((await api(`/api/bookings/${booking.id}/location-sharing`,{token:farmer.token,method:'PATCH',body:{enabled:true}})).status,403);
 await api('/api/me',{token:provider.token,method:'PATCH',body:{lat:17.66,lng:75.91}});
 assert.equal((await api('/api/bookings',{token:farmer.token})).data.bookings[0].providerLocation,null);
 assert.equal((await api(`/api/bookings/${booking.id}/location-sharing`,{token:provider.token,method:'PATCH',body:{enabled:true}})).status,200);
 const tracking=(await api('/api/bookings',{token:farmer.token})).data.bookings[0];assert.equal(tracking.providerLocation.lat,17.66);assert.ok(tracking.providerLocation.updatedAt);
 assert.equal((await api('/api/bookings',{token:other.token})).data.bookings[0].providerLocation,null);
 assert.equal((await api('/api/teams')).data.teams[0].providerLocation,undefined);

 assert.equal((await api(`/api/bookings/${second.id}/status`,{token:provider.token,method:'PATCH',body:{status:'accepted'}})).status,409);
 assert.equal((await api('/api/bookings',{token:other.token,body:request()})).status,409);
 assert.equal((await api(`/api/bookings/${booking.id}/status`,{token:farmer.token,method:'PATCH',body:{status:'completed'}})).status,409);
 assert.equal((await api(`/api/bookings/${booking.id}/status`,{token:farmer.token,method:'PATCH',body:{status:'cancelled'}})).status,200);assert.equal((await api('/api/bookings',{token:farmer.token})).data.bookings[0].providerLocation,null);
 assert.equal((await api(`/api/bookings/${second.id}/status`,{token:provider.token,method:'PATCH',body:{status:'accepted'}})).status,200);
 assert.equal((await api(`/api/bookings/${second.id}/status`,{token:provider.token,method:'PATCH',body:{status:'completed'}})).status,200);
 assert.equal((await api(`/api/bookings/${second.id}/status`,{token:provider.token,method:'PATCH',body:{status:'declined'}})).status,409);assert.equal((await api('/api/bookings',{token:farmer.token,body:request()})).status,409);
});
test('GPS coordinates persist for the account; logout revokes access',async()=>{
 const res=await api('/api/me',{token:farmer.token,method:'PATCH',body:{lat:17.7,lng:75.8,address:'My village farm'}});assert.equal(res.status,200);assert.equal(res.data.user.lat,17.7);
 assert.equal((await api('/api/me',{token:other.token})).data.user.lat,null);
 assert.equal((await api('/api/me',{token:other.token,method:'PATCH',body:{lat:'17.7',lng:75.8}})).status,400);
 await api('/api/auth/logout',{token:other.token,body:{}});assert.equal((await api('/api/me',{token:other.token})).status,401);
});
test('KVK admin login requires forced password change and does not allow public admin registration',async()=>{
 assert.equal((await api('/api/auth/register',{body:{phone:'9333333333',password:'strong-password-123',name:'Pretend Admin',age:35,address:'Solapur',role:'admin'}})).status,400);
 assert.equal((await api('/api/admin/login',{body:{phone:'9333333333',password:'wrong-password'}})).status,401);
 const login=await api('/api/admin/login',{body:{phone:'9333333333',password:'Temporary-admin-123'}});assert.equal(login.status,200);admin=login.data;
 assert.equal(admin.user.role,'admin');assert.equal(admin.user.mustChangePassword,true);
 assert.equal((await api('/api/admin/users',{token:admin.token})).status,403);
 assert.equal((await api('/api/admin/users',{token:farmer.token})).status,403);
 assert.equal((await api('/api/admin/password',{token:admin.token,method:'PATCH',body:{currentPassword:'wrong-password',newPassword:'New-strong-password-123'}})).status,401);
 assert.equal((await api('/api/admin/password',{token:admin.token,method:'PATCH',body:{currentPassword:'Temporary-admin-123',newPassword:'New-strong-password-123'}})).status,200);
 assert.equal((await api('/api/admin/login',{body:{phone:'9333333333',password:'Temporary-admin-123'}})).status,401);
 assert.equal((await api('/api/admin/users',{token:admin.token})).status,200);
});
test('KVK admin can verify and hide teams, suspend accounts, cancel bookings and see audit',async()=>{
 const overview=(await api('/api/admin/overview',{token:admin.token})).data.counts;assert.equal(overview.providers,1);assert.equal(overview.farmers,2);
 assert.equal((await api('/api/admin/teams',{token:farmer.token})).status,403);
 assert.equal((await api(`/api/admin/teams/${team.id}`,{token:admin.token,method:'PATCH',body:{verified:true}})).status,200);
 assert.equal((await api('/api/teams')).data.teams[0].verified,true);
 assert.equal((await api(`/api/admin/teams/${team.id}`,{token:admin.token,method:'PATCH',body:{adminHidden:true}})).status,200);
 assert.equal((await api('/api/teams')).data.teams.length,0);
 assert.equal((await api('/api/bookings',{token:farmer.token,body:request()})).status,409);
 await api(`/api/admin/teams/${team.id}`,{token:admin.token,method:'PATCH',body:{adminHidden:false}});
 const pending=(await api('/api/bookings',{token:farmer.token,body:request({workers:1})})).data.booking;
 assert.equal((await api(`/api/admin/bookings/${pending.id}/cancel`,{token:admin.token,body:{reason:'Farmer called KVK to cancel'}})).status,200);
 assert.equal((await api('/api/bookings',{token:farmer.token})).data.bookings[0].status,'cancelled');
 assert.equal((await api(`/api/admin/users/${provider.user.id}`,{token:admin.token,method:'PATCH',body:{suspended:true}})).status,200);
 assert.equal((await api('/api/me',{token:provider.token})).status,401);
 assert.equal((await api('/api/teams')).data.teams.length,0);
 await api(`/api/admin/users/${provider.user.id}`,{token:admin.token,method:'PATCH',body:{suspended:false}});
 assert.equal((await api('/api/teams')).data.teams.length,1);
 assert.equal((await api('/api/admin/audit',{token:admin.token})).data.events.some(e=>e.action==='booking_cancelled'),true);
 assert.equal((await api('/api/admin/bookings',{token:admin.token})).data.bookings.length>0,true);
 assert.equal((await api('/api/admin/admins',{token:admin.token})).data.admins.length,1);
 assert.equal((await api('/api/admin/admins',{token:admin.token,body:{name:'Second Admin',phone:'9444444444',password:'New-admin-pass-123'}})).status,201);
 assert.equal((await api('/api/admin/login',{body:{phone:'9444444444',password:'New-admin-pass-123'}})).data.user.mustChangePassword,true);
});
test('data survives a database restart',async()=>{
 await app.close();app=createApp({dbPath:join(dir,'test.sqlite')});await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));base=`http://127.0.0.1:${app.server.address().port}`;
 assert.equal((await api('/api/bookings',{token:farmer.token})).data.bookings.some(x=>x.id===booking.id),true);
 assert.equal((await api('/api/teams')).data.teams[0].name,'Local Team');
});
