// Email preferences (NOTIF-13): the form's rules match the database's CHECK constraints.
import { describe, expect, it } from 'vitest';
import { channelSave } from '../../src/lib/validation/channels';

const base = { quiet_start: '21:00', quiet_end: '07:00', reminder_lead_hours: '2' };

describe('channelSave', () => {
  it('reads the lead time from the form and keeps the chosen types', () => {
    const parsed = channelSave.parse({ ...base, email: ['reminder'] });
    expect(parsed.reminder_lead_hours).toBe(2);
    expect(parsed.email).toEqual(['reminder']);
  });

  it('allows only 1, 2, 6 or 24 hours', () => {
    expect(channelSave.safeParse({ ...base, reminder_lead_hours: '3' }).success).toBe(false);
    expect(channelSave.safeParse({ ...base, reminder_lead_hours: '24' }).success).toBe(true);
  });

  it('needs both quiet hours, in HH:MM', () => {
    expect(channelSave.safeParse({ ...base, quiet_start: '9pm' }).success).toBe(false);
    expect(channelSave.safeParse({ ...base, quiet_end: '' }).success).toBe(false);
  });

  it('treats no checked types as none, not as an error', () => {
    expect(channelSave.parse(base).email).toEqual([]);
  });
});
