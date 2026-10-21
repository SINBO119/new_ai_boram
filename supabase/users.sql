-- users: 요금제를 신청하는 사용자 1명
-- Supabase 대시보드 > SQL Editor에서 한 번 실행한다. 다시 실행해도 오류가 나지 않게 썼다.
-- 다른 테이블 없이 혼자 실행된다.
-- 로그인(본인 인증)은 PRD 6장에서 범위 밖이라, 사용자 ID는 저장 시 DB가 만든다.

create table if not exists public.users (
  -- 사용자 ID. 저장 시 생성
  id                  uuid        primary key default gen_random_uuid(),
  -- 사용자명. 앞뒤 공백 빼고 1~50자
  name                text        not null check (char_length(btrim(name)) between 1 and 50),
  -- 휴대폰 번호. 숫자 11자리. 같은 번호로 두 번 가입하지 못한다
  phone               text        not null unique check (phone ~ '^[0-9]{11}$'),
  -- 개인정보 수집·이용 동의(필수). true일 때만 저장
  agreed_privacy      boolean     not null check (agreed_privacy = true),
  -- 개인정보 동의 일시. 동의 증빙용
  privacy_agreed_at   timestamptz not null default now(),
  -- 마케팅 정보 수신 동의(선택)
  agreed_marketing    boolean     not null default false,
  -- 마케팅 동의 일시. 동의하지 않았으면 null
  marketing_agreed_at timestamptz,
  -- 상태: active(이용 중) | withdrawn(탈퇴). 탈퇴해도 신청 기록과 연결을 지키려고 행은 지우지 않는다
  status              text        not null default 'active' check (status in ('active', 'withdrawn')),
  -- 가입 일시. 저장 시 생성
  created_at          timestamptz not null default now(),
  -- 마지막 수정 일시. 수정할 때 트리거가 바꾼다
  updated_at          timestamptz not null default now(),
  -- 마케팅에 동의했으면 동의 일시가 있어야 한다
  check (agreed_marketing = false or marketing_agreed_at is not null)
);

comment on table public.users is '요금제를 신청하는 사용자 1명';

-- 수정할 때마다 updated_at을 지금 시각으로 바꾼다
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists users_set_updated_at on public.users;
create trigger users_set_updated_at
  before update on public.users
  for each row execute function public.set_updated_at();

-- RLS 켜기: 정책에 없는 동작은 모두 거부된다
alter table public.users enable row level security;

-- 공개 키(anon)로 가입(저장)만 허용. 값 규칙은 위 check 제약이 막는다
drop policy if exists "anon can insert users" on public.users;
create policy "anon can insert users"
  on public.users
  for insert
  to anon
  with check (true);

-- 공개 키로 전체 조회는 허용하지 않는다 (공개 키는 브라우저에 그대로 보이므로, 열면 모든 사용자의 이름·번호가 노출된다).
-- 대신 사용자 ID를 아는 경우에만 그 1명을 돌려주는 함수를 연다.
create or replace function public.get_user(p_id uuid)
returns table (id uuid, name text, phone text, agreed_marketing boolean, status text, created_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select u.id, u.name, u.phone, u.agreed_marketing, u.status, u.created_at
  from public.users u
  where u.id = p_id;
$$;

revoke all on function public.get_user(uuid) from public;
grant execute on function public.get_user(uuid) to anon;

-- 수정 · 삭제는 정책이 없어 RLS가 막는다. 권한에서도 한 번 더 뺀다
revoke update, delete, truncate on public.users from anon, authenticated;
