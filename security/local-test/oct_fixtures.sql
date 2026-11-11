insert into merchants(id,name,phone,pin_hash,status) values
 ('11111111-1111-1111-1111-111111111111','A','71111111',extensions.crypt('1234',extensions.gen_salt('bf',4)),'active'),
 ('22222222-2222-2222-2222-222222222222','B','72222222',extensions.crypt('5678',extensions.gen_salt('bf',4)),'active');
insert into admin_users(id,username,pin_hash,is_primary) values
 ('33333333-3333-3333-3333-333333333333','primary_admin',extensions.crypt('9999',extensions.gen_salt('bf',4)),true),
 ('44444444-4444-4444-4444-444444444444','secondary_admin',extensions.crypt('8888',extensions.gen_salt('bf',4)),false);
