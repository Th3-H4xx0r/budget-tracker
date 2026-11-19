import { afterEach, beforeEach, describe, expect, it } from '@jest/globals';
import * as helpers from '@tests/helpers';

const DEFAULT_USER_EMAIL = 'test1@test.local';

describe('Admin access via ADMIN_USERS email', () => {
  let originalAdminUsers: string | undefined;

  beforeEach(() => {
    originalAdminUsers = process.env.ADMIN_USERS;
  });

  afterEach(() => {
    if (originalAdminUsers === undefined) delete process.env.ADMIN_USERS;
    else process.env.ADMIN_USERS = originalAdminUsers;
  });

  it('allows an admin endpoint when ADMIN_USERS lists the account email', async () => {
    process.env.ADMIN_USERS = DEFAULT_USER_EMAIL;
    const { id } = await helpers.getUserInfo({ raw: true });

    const res = await helpers.adminUpdateUserPlan({ userId: id, payload: { plan: null } });
    expect(res.statusCode).toBe(200);
  });

  it('matches the email case-insensitively and ignores surrounding whitespace', async () => {
    process.env.ADMIN_USERS = `other, ${DEFAULT_USER_EMAIL.toUpperCase()} `;
    const { id } = await helpers.getUserInfo({ raw: true });

    const res = await helpers.adminUpdateUserPlan({ userId: id, payload: { plan: null } });
    expect(res.statusCode).toBe(200);
  });

  it('denies an admin endpoint when ADMIN_USERS lists a different email', async () => {
    process.env.ADMIN_USERS = 'someone-else@test.local';
    const { id } = await helpers.getUserInfo({ raw: true });

    const res = await helpers.adminUpdateUserPlan({ userId: id, payload: { plan: null } });
    expect(res.statusCode).toBe(401);
  });

  it('flags GET /user isAdmin when ADMIN_USERS lists the account email in another case', async () => {
    process.env.ADMIN_USERS = DEFAULT_USER_EMAIL.toUpperCase();

    const user = await helpers.getUserInfo({ raw: true });
    expect(user.isAdmin).toBe(true);
  });

  it('does not flag GET /user isAdmin for a different email', async () => {
    process.env.ADMIN_USERS = 'someone-else@test.local';

    const user = await helpers.getUserInfo({ raw: true });
    expect(user.isAdmin).toBe(false);
  });
});
