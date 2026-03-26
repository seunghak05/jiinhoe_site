-- ================================================
-- 지인회 관리자 시스템 — Supabase SQL 설정 (v2)
-- Supabase 대시보드 > SQL Editor 에서 전체 실행
-- 기존 데이터가 있어도 DROP 후 재생성하므로 안전합니다
-- ================================================

-- ── 기존 함수 제거 ──
drop function if exists public.get_my_profile() cascade;
drop function if exists public.admin_get_profiles() cascade;
drop function if exists public.admin_set_approved(uuid, boolean) cascade;
drop function if exists public.admin_set_role(uuid, text) cascade;
drop function if exists public.admin_delete_profile(uuid) cascade;
drop function if exists public.handle_new_user() cascade;

-- ── 기존 트리거 제거 ──
drop trigger if exists on_auth_user_created on auth.users;

-- ── 기존 테이블 제거 (순서 중요) ──
drop table if exists public.gallery  cascade;
drop table if exists public.dojangs  cascade;
drop table if exists public.members  cascade;
drop table if exists public.awards   cascade;
drop table if exists public.settings cascade;
drop table if exists public.profiles cascade;

-- ── Storage 정책 제거 ──
drop policy if exists "Public read gallery storage"   on storage.objects;
drop policy if exists "Admins upload gallery storage" on storage.objects;
drop policy if exists "Admins delete gallery storage" on storage.objects;
drop policy if exists "Public gallery read"           on storage.objects;
drop policy if exists "Auth gallery upload"           on storage.objects;
drop policy if exists "Auth gallery delete"           on storage.objects;

-- ================================================
-- 테이블 생성
-- ================================================

create table public.profiles (
  id         uuid references auth.users on delete cascade primary key,
  email      text not null,
  name       text not null default '',
  role       text not null default 'admin' check (role in ('super_admin', 'admin')),
  approved   boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.awards (
  id         bigserial primary key,
  year       int not null,
  date       text not null default '',
  name       text not null,
  results    text[] not null default '{}',
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table public.members (
  id         bigserial primary key,
  name       text not null,
  role_text  text not null default '',
  badge      text not null default '',
  sort_order int not null default 0
);

create table public.dojangs (
  id         bigserial primary key,
  name       text not null,
  region     text not null default '',
  map_link   text not null default '',
  sort_order int not null default 0
);

create table public.gallery (
  id         bigserial primary key,
  url        text not null,
  caption    text not null default '',
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table public.settings (
  key        text primary key,
  value      text not null default '',
  updated_at timestamptz not null default now()
);

-- ================================================
-- RLS 활성화
-- ================================================

alter table public.profiles enable row level security;
alter table public.awards   enable row level security;
alter table public.members  enable row level security;
alter table public.dojangs  enable row level security;
alter table public.gallery  enable row level security;
alter table public.settings enable row level security;

-- ── 공개 읽기 정책 ──
create policy "Public read awards"   on public.awards   for select using (true);
create policy "Public read members"  on public.members  for select using (true);
create policy "Public read dojangs"  on public.dojangs  for select using (true);
create policy "Public read gallery"  on public.gallery  for select using (true);
create policy "Public read settings" on public.settings for select using (true);

-- ── 프로필: 본인만 읽기/삽입 (임원 관리는 security definer 함수로) ──
create policy "Users read own profile"   on public.profiles for select using (auth.uid() = id);
create policy "Users insert own profile" on public.profiles for insert with check (auth.uid() = id);

-- ── 콘텐츠 쓰기: 승인된 관리자 (security definer 함수로 profiles 조회 → 재귀 없음) ──
create or replace function public.is_approved_admin()
returns boolean language sql security definer stable as $$
  select exists (select 1 from public.profiles where id = auth.uid() and approved = true)
$$;

create policy "Admins write settings" on public.settings for all
  using (public.is_approved_admin()) with check (public.is_approved_admin());

create policy "Admins all awards"   on public.awards  for all
  using (public.is_approved_admin()) with check (public.is_approved_admin());

create policy "Admins all members"  on public.members for all
  using (public.is_approved_admin()) with check (public.is_approved_admin());

create policy "Admins all dojangs"  on public.dojangs for all
  using (public.is_approved_admin()) with check (public.is_approved_admin());

create policy "Admins all gallery"  on public.gallery for all
  using (public.is_approved_admin()) with check (public.is_approved_admin());

-- ================================================
-- Security Definer 함수 (RLS 우회용)
-- ================================================

-- 내 프로필 조회 (로그인 확인용)
create or replace function public.get_my_profile()
returns json language plpgsql security definer as $$
declare r record;
begin
  select id, email, name, role, approved into r
  from public.profiles where id = auth.uid();
  if not found then return null; end if;
  return row_to_json(r);
end;
$$;

-- 임원: 전체 회원 목록 조회
create or replace function public.admin_get_profiles()
returns setof public.profiles language plpgsql security definer as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'super_admin' and approved = true
  ) then raise exception 'Forbidden'; end if;
  return query select * from public.profiles order by approved, created_at;
end;
$$;

-- 임원: 승인 처리
create or replace function public.admin_set_approved(target_id uuid, new_approved boolean)
returns void language plpgsql security definer as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'super_admin' and approved = true
  ) then raise exception 'Forbidden'; end if;
  update public.profiles set approved = new_approved where id = target_id;
end;
$$;

-- 임원: 역할 변경
create or replace function public.admin_set_role(target_id uuid, new_role text)
returns void language plpgsql security definer as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'super_admin' and approved = true
  ) then raise exception 'Forbidden'; end if;
  update public.profiles set role = new_role where id = target_id;
end;
$$;

-- 임원: 회원 삭제
create or replace function public.admin_delete_profile(target_id uuid)
returns void language plpgsql security definer as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'super_admin' and approved = true
  ) then raise exception 'Forbidden'; end if;
  delete from public.profiles where id = target_id;
end;
$$;

-- ================================================
-- 회원가입 시 프로필 자동 생성 트리거
-- ================================================

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
declare
  cnt int;
begin
  select count(*) into cnt from public.profiles where approved = true;
  insert into public.profiles (id, email, name, role, approved)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'name', ''),
    case when cnt = 0 then 'super_admin' else 'admin' end,
    cnt = 0
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ================================================
-- Storage 버킷 및 정책
-- ================================================

insert into storage.buckets (id, name, public)
values ('gallery', 'gallery', true)
on conflict (id) do update set public = true;

create policy "Public gallery read" on storage.objects
  for select using (bucket_id = 'gallery');

create policy "Auth gallery upload" on storage.objects
  for insert with check (bucket_id = 'gallery' and auth.uid() is not null);

create policy "Auth gallery delete" on storage.objects
  for delete using (bucket_id = 'gallery' and auth.uid() is not null);

-- ================================================
-- 기본 데이터 (seed data)
-- ================================================

-- 사이트 설정 기본값
insert into public.settings (key, value) values
  ('hero_thin',       '뜻을 모아'),
  ('hero_red',        '한계를 깎다'),
  ('hero_sub',        '지인회(志人會)는 전북특별자치도 태권도 품새 전문 선수단입니다.\n체계적인 훈련과 단합된 팀워크를 바탕으로 실력을 증명해 나갑니다.'),
  ('hero_cta',        '지인회 소개'),
  ('contact_phone',   '0507-1448-7577'),
  ('contact_org',     '용인대 마스터 태권도'),
  ('hero_slideshow',  '["img/train1.jpg","img/train2.jpg","img/train3.jpg","img/01.jpg","img/05.jpg","img/06.jpg","img/07.jpg","img/08.jpg","img/10.jpg","img/13.jpg","img/14.jpg"]');

-- 회원명단
insert into public.members (name, role_text, badge, sort_order) values
  ('정인수', '지인회태권도 관장', '명예회원', 1),
  ('김민화', '용인대마스터태권도 관장', '', 2),
  ('박미선', '군산시', '', 3),
  ('김수일', '원광대학교', '', 4),
  ('장명진', '프리랜서 지도자·팀어게인 전주점', '', 5),
  ('이진규', '평화 효자태권도장 관장', '', 6),
  ('조광익', '히어로키즈태권도장 관장', '', 7),
  ('김 선', '정읍시', '', 8),
  ('이동혁', '삼례경희대태권도장 관장', '', 9),
  ('조명성', '태양태권도 관장', '', 10),
  ('김찬울', '찬빛태권도장 관장', '', 11),
  ('유향미', '탑클래스태권도장 관장', '', 12),
  ('변동아', '송천 효경석사 태권도', '', 13),
  ('양지은', '히어로키즈태권도', '', 14);

-- 소속도장
insert into public.dojangs (name, region, map_link, sort_order) values
  ('삼례경희대태권도장',   '완주군', 'https://naver.me/xDJdm8kY', 1),
  ('송천 효경석사 태권도', '전주시', 'https://naver.me/GlJBEbJL', 2),
  ('팀 어게인 전주점',     '전주시', 'https://naver.me/xS1QIpVn', 3),
  ('용인대마스터태권도',   '전주시', 'https://naver.me/5zX5EsYT', 4),
  ('찬빛태권도장',         '진안군', 'https://naver.me/FqWACESi', 5),
  ('탑클래스태권도장',     '전주시', 'https://naver.me/FMce94en', 6),
  ('태양태권도',           '군산시', 'https://naver.me/G7VmbQgB', 7),
  ('평화 효자태권도장',    '전주시', 'https://naver.me/FUQyNTtn', 8),
  ('히어로키즈태권도장',   '군산시', 'https://naver.me/xUwPQiXf', 9);

-- 갤러리 (기존 로컬 이미지)
insert into public.gallery (url, caption, sort_order) values
  ('img/train1.jpg', '정기수련', 1),
  ('img/train2.jpg', '정기수련', 2),
  ('img/train3.jpg', '정기수련', 3),
  ('img/01.jpg', '정기수련', 4),
  ('img/02.jpg', '대회', 5),
  ('img/03.jpg', '대회', 6),
  ('img/04.jpg', '대회', 7),
  ('img/05.jpg', '정기수련', 8),
  ('img/06.jpg', '정기수련', 9),
  ('img/07.jpg', '입회식', 10),
  ('img/08.jpg', '정기수련', 11),
  ('img/09.jpg', '대회', 12),
  ('img/10.jpg', '정기수련', 13),
  ('img/11.jpg', '단체사진', 14),
  ('img/12.jpg', '대회', 15),
  ('img/13.jpg', '정기수련', 16),
  ('img/14.jpg', '정기수련', 17);

-- 수상내역
insert into public.awards (year, date, name, results, sort_order) values
(2026, '3월 16일', '2026 전국종별선수권대회', ARRAY['남자 지태 1부 3위: 조명성'], 1),
(2026, '2월 25일~28일', '2026년도 국가대표 선발전 아시아·세계선수권', ARRAY['아시아선수권대회 1위: 장명진','세계선수권대회 4위: 김민화'], 2),
(2025, '11월 1일', '제22회 대한태권도협회장배 대회', ARRAY['태백 2부 여 개인전 1위: 장명진','장년 2부 페어 2위: 이진규, 김민화','천권부 남 개인전 3위: 이진규'], 3),
(2025, '8월 8일', '제60회 대통령기 전국단체대항태권도대회', ARRAY['태백 2부 여 1위: 장명진','금강 2부 여 2위: 유향미','천권부 남 3위: 이진규'], 4),
(2025, '7월 26일', '제11회 태권도원배 전국태권도선수권대회', ARRAY['천권부 여자 3위: 박미선'], 5),
(2025, '7월 19일', '계명대 총장기 대회', ARRAY['태백2부 여자 1위: 장명진','장년1부 복식전 3위: 이홍원, 장명진'], 6),
(2025, '7월 19일', '제18회 세계태권도 엑스포대회', ARRAY['개인전 1위: 이진규'], 7),
(2025, '7월 5일', '우석대 총장기 전국태권도 대회', ARRAY['천권부 여 1위: 김민화','천권부 남 2위: 이진규','천권부 여 2위: 박미선'], 8),
(2025, '6월 15일', '제23회 한국여성태권도연맹회장기 전국태권도대회', ARRAY['금강 2부 여 2위: 유향미','천권부 남 3위: 이진규'], 9),
(2025, '5월 4일', '제3회 전주대총장기 전국태권도대회', ARRAY['태백 2부 여 1위: 장명진','천권부 여 1위: 김민화','천권부 남 3위: 이진규'], 10),
(2024, '12월 2일', '2024년 홍콩품새선수권대회', ARRAY['은메달: 장명진 (여 단체전, +30세 이상)'], 11),
(2024, '8월 5일', '2024년 세계태권도선수권대회 최종전', ARRAY['2위: 장명진 (-40세 이하)','3위: 장명진 (+30세 이상 통합단체전, 국가대표 발탁)'], 12),
(2024, '7월 20일', '2024년 제17회 무주태권도원 문화엑스포대회', ARRAY['2위: 유향미 (개인전 2부, 시니어1)','3위: 조명성, 이동혁 (개인전 1부, 시니어2)'], 13),
(2024, '5월 26일', '제21회 계명대학교총장기 태권도대회', ARRAY['3위: 이동혁, 김민화 (페어전, 장년부)'], 14),
(2024, '5월 12일', '제8회 아시아 품새선수권대회', ARRAY['1위: 장명진 (페어전, +30세 이상)'], 15),
(2024, '5월 14일', '2024년 전북특별자치도 태권도한마당대회', ARRAY['1위: 이동혁 (개인전, 태백부)','2위: 조명성 (개인전, 태백부)','시도대항 감투상: 조명성, 조광익'], 16),
(2024, '3월 30일', '제18회 한국실업태권도연맹회장기', ARRAY['1위: 장명진 (개인전, 태백1부)','3위: 김동현, 장명진 (페어전, 장년부)'], 17),
(2024, '2월 24일', '2024년 아시아 선수권대회 선발전', ARRAY['2위: 장명진 (-40세 이하, 페어전 국가대표 발탁)','3위: 김민화 (-50세 이하)'], 18),
(2024, '2월 23일', '2024년 세계선수권대회 선발전', ARRAY['1위: 장명진 (-40세 이하)','3위: 김민화 (-50세 이하)'], 19),
(2024, '2월 3일', '제19회 제주평화기 전국태권도대회', ARRAY['1위: 김동현 (지태2부)'], 20),
(2023, '11월 27일', '제20회 대한태권도협회장배 전국태권도품새선수권대회', ARRAY['지태 2부 여 1위: 박미선','태백 1부 여 2위: 장명진','지태 2부 남 3위: 김동현','지태 2부 여 3위: 김민화'], 21),
(2023, '8월 6일', '2023년 우석대총장기 태권도대회', ARRAY['지태 2부 2위: 박미선','지태 2부 3위: 김민화'], 22),
(2023, '8월 2일', '2023 김운용컵 국제오픈 태권도대회', ARRAY['-50 여자 2위: 박미선','-50 남자 3위: 김동현'], 23),
(2023, '7월 16일', '여성연맹 태권도대회', ARRAY['지태2부 2위: 이진규','지태 1부 3위: 김선'], 24),
(2023, '6월 3일', '제14회 나사렛대학교총장기대회', ARRAY['지태 2부 남 1위: 김동현','태백 1부 여 1위: 장명진','지태 2부 남 2위: 이진규','페어 장년부 2위: 김동현, 김민화','페어 장년부 3위: 이진규, 박미선'], 25),
(2023, '5월 14일', '아시아태평양마스터즈대회', ARRAY['-50 남 개인전 1위: 김동현','-40 여 개인전 1위: 장명진','-50 여 개인전 1위: 박미선','+30이상 페어전 1위: 김동현, 장명진','+30이상 남 단체전 1위: 김동현, 이진규, 이현재','+30이상 여 단체전 1위: 김민화, 박미선, 장명진','-45 여 개인전 2위: 김선','-50 여 개인전 2위: 김민화','-50 남 개인전 3위: 이진규','+30이상 페어전 3위: 이진규, 박미선'], 26),
(2023, '5월 7일', '제1회 전주대총장기 대회', ARRAY['지태 1부 3위: 김선'], 27),
(2023, '', '성남한마당대회', ARRAY['시니어3 2위: 김동현'], 28),
(2023, '', '제35회 도지사배 태권도대회 겸 전국체전 선발전', ARRAY['-30 3위: 김수일 (전라북도 대표 선발)'], 29),
(2023, '', '한마당대회 및 전국체전 2차 선발전', ARRAY['-30 3위: 김수일'], 30),
(2022, '2월 12일', '2022 국가대표선발전', ARRAY['지태2부 3위: 김민화'], 31),
(2022, '2월 8일', '제19회 대한태권도협회 품새선수권대회', ARRAY['여자 지태2부 2위: 김민화','태백1부 3위: 장명진','남자 지태2부 3위: 김동현'], 32),
(2022, '', '제2회 신한대학교 총장기 전국태권도대회', ARRAY['개인전 지태2부 1위: 김민화','개인전 지태2부 2위: 김동현','개인전 지태2부 2위: 박미선','복식전 3위: 지인회A (박미선, 이진규)','복식전 3위: 지인회B (김민화, 김동현)'], 33),
(2021, '11월 27일', '제16회 전주비전대학교총장배 태권도대회', ARRAY['개인전 1부 1위: 장명진','개인전 1부 1위: 김수일','개인전 2부 1위: 이진규','단체전 2위 (장명진, 김수일, 이진규)'], 34),
(2021, '6월 19일', '제18회 대한태권도협회장배 품새선수권대회', ARRAY['여자 지태2부 1위: 김민화','여자 지태2부 2위: 박미선','남자 지태2부 2위: 김동현'], 35),
(2020, '7월 22일', '제13회 세계태권도문화엑스포', ARRAY['단체전 3위 (김민화, 박미선, 김동현)'], 36);

-- ================================================
-- 최초 임원 설정 방법
-- 1. login.html 에서 계정 회원가입
-- 2. 아래 이메일을 실제 이메일로 바꿔서 실행:
-- UPDATE public.profiles SET role = 'super_admin', approved = true WHERE email = '여기에_이메일_입력';
-- ================================================
