import {test,expect} from '@playwright/test';

test('KVK admin signs in, changes temporary password, and manages records',async({page,request})=>{
 const provider=await request.post('/api/auth/register',{data:{name:'Admin Test Provider',phone:'9555555555',password:'provider-password-123',age:35,address:'Solapur',role:'provider'}});
 expect(provider.ok()).toBeTruthy();const providerToken=(await provider.json()).token;
 const team=await request.put('/api/provider/team',{headers:{Authorization:`Bearer ${providerToken}`},data:{name:'KVK Review Team',place:'Solapur',crops:['Grape'],skills:['Harvesting'],people:4,price:500,lat:17.65,lng:75.9,available:true}});expect(team.ok()).toBeTruthy();
 const teamId=(await team.json()).team.id;
 await page.goto('/admin');await expect(page.getByRole('heading',{name:'Admin sign in'})).toBeVisible();
 await page.locator('[name=phone]').fill('9333333333');await page.locator('[name=password]').fill('Temporary-admin-123');await page.locator('#login-form button').click();
 await expect(page.getByRole('heading',{name:'Change temporary password'})).toBeVisible();
 await page.locator('[name=currentPassword]').fill('Temporary-admin-123');await page.locator('[name=newPassword]').fill('Permanent-admin-password-123');await page.locator('[name=confirm]').fill('Permanent-admin-password-123');await page.locator('#change-form button').click();
 await expect(page.getByRole('heading',{name:'Overview'})).toBeVisible();
 await page.locator('nav [data-section=teams]').click();await expect(page.locator('tbody')).toContainText('KVK Review Team');
 page.on('dialog',dialog=>dialog.accept());await page.locator(`[data-team="${teamId}"][data-verified]`).click();await expect(page.locator('tbody')).toContainText('Verified');
 await page.locator(`[data-team="${teamId}"][data-hidden]`).click();await expect(page.locator('tbody')).toContainText('Hidden');
 const publicTeams=await request.get('/api/teams');expect((await publicTeams.json()).teams.some(t=>t.id===teamId)).toBe(false);
 await page.locator('nav [data-section=users]').click();await expect(page.locator('tbody')).toContainText('Admin Test Provider');
 await page.locator('nav [data-section=audit]').click();await expect(page.locator('tbody')).toContainText('team updated');
 await page.locator('#signout').click();await expect(page.getByRole('heading',{name:'Admin sign in'})).toBeVisible();
});
