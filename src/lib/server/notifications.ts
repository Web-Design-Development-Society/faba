// Where an opened notification goes, for tapping it in Alerts (NOTIF-01) and for tapping a push
// (NOTIF-20). It reads as the signed-in member, so only their own notifications open anywhere.
import { notificationHref } from '../notifications';
import type { Supabase } from './supabase';

export async function openedHref(supabase: Supabase, id: string): Promise<string> {
  const { data } = await supabase
    .from('notifications')
    .select('type, activity_id, payload, group:groups(slug)')
    .eq('id', id)
    .maybeSingle();
  return data ? notificationHref({ ...data, group_slug: data.group?.slug }) : '/notifications';
}
