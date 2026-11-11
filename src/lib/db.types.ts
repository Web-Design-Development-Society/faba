export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Database = {
  public: {
    Tables: {
      activities: {
        Row: {
          announced_at: string | null;
          cancel_reason: string | null;
          cancelled_at: string | null;
          capacity: number | null;
          category_id: string;
          copied_from_id: string | null;
          cost_note: string | null;
          created_at: string;
          description: string | null;
          ends_at: string | null;
          going_count: number;
          group_id: string | null;
          guest_total: number;
          guests_allowed: boolean;
          has_private_details: boolean;
          hidden_at: string | null;
          hidden_by: string | null;
          hidden_reason: string | null;
          id: string;
          idempotency_key: string | null;
          is_board_activity: boolean;
          location_name: string;
          max_guests_per_rsvp: number;
          maybe_count: number;
          organizer_id: string | null;
          search_doc: unknown;
          series_detached: boolean;
          series_id: string | null;
          starts_at: string;
          status: string;
          time_or_place_changed_at: string | null;
          timezone: string;
          title: string;
          updated_at: string;
          version: number;
          visibility: string;
          my_rsvp: string | null;
        };
        ComputedFields: 'my_rsvp';
        Insert: {
          announced_at?: string | null;
          cancel_reason?: string | null;
          cancelled_at?: string | null;
          capacity?: number | null;
          category_id: string;
          copied_from_id?: string | null;
          cost_note?: string | null;
          created_at?: string;
          description?: string | null;
          ends_at?: string | null;
          going_count?: number;
          group_id?: string | null;
          guest_total?: number;
          guests_allowed?: boolean;
          has_private_details?: boolean;
          hidden_at?: string | null;
          hidden_by?: string | null;
          hidden_reason?: string | null;
          id?: string;
          idempotency_key?: string | null;
          is_board_activity?: boolean;
          location_name: string;
          max_guests_per_rsvp?: number;
          maybe_count?: number;
          organizer_id?: string | null;
          search_doc?: never;
          series_detached?: boolean;
          series_id?: string | null;
          starts_at: string;
          status?: string;
          time_or_place_changed_at?: string | null;
          timezone?: string;
          title: string;
          updated_at?: string;
          version?: number;
          visibility?: string;
        };
        Update: {
          announced_at?: string | null;
          cancel_reason?: string | null;
          cancelled_at?: string | null;
          capacity?: number | null;
          category_id?: string;
          copied_from_id?: string | null;
          cost_note?: string | null;
          created_at?: string;
          description?: string | null;
          ends_at?: string | null;
          going_count?: number;
          group_id?: string | null;
          guest_total?: number;
          guests_allowed?: boolean;
          has_private_details?: boolean;
          hidden_at?: string | null;
          hidden_by?: string | null;
          hidden_reason?: string | null;
          id?: string;
          idempotency_key?: string | null;
          is_board_activity?: boolean;
          location_name?: string;
          max_guests_per_rsvp?: number;
          maybe_count?: number;
          organizer_id?: string | null;
          search_doc?: never;
          series_detached?: boolean;
          series_id?: string | null;
          starts_at?: string;
          status?: string;
          time_or_place_changed_at?: string | null;
          timezone?: string;
          title?: string;
          updated_at?: string;
          version?: number;
          visibility?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'activities_category_id_fkey';
            columns: ['category_id'];
            isOneToOne: false;
            referencedRelation: 'categories';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'activities_copied_from_id_fkey';
            columns: ['copied_from_id'];
            isOneToOne: false;
            referencedRelation: 'activities';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'activities_group_id_fkey';
            columns: ['group_id'];
            isOneToOne: false;
            referencedRelation: 'groups';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'activities_hidden_by_fkey';
            columns: ['hidden_by'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'activities_organizer_id_fkey';
            columns: ['organizer_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'activities_series_id_fkey';
            columns: ['series_id'];
            isOneToOne: false;
            referencedRelation: 'activity_series';
            referencedColumns: ['id'];
          },
        ];
      };
      activity_co_organizers: {
        Row: {
          activity_id: string;
          added_at: string;
          added_by: string | null;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          activity_id: string;
          added_at?: string;
          added_by?: string | null;
          user_id: string;
        };
        Update: {
          activity_id?: string;
          added_at?: string;
          added_by?: string | null;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'activity_co_organizers_activity_id_fkey';
            columns: ['activity_id'];
            isOneToOne: false;
            referencedRelation: 'activities';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'activity_co_organizers_added_by_fkey';
            columns: ['added_by'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'activity_co_organizers_user_id_fkey';
            columns: ['user_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      activity_mutes: {
        Row: {
          activity_id: string;
          muted_at: string;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          activity_id: string;
          muted_at?: string;
          user_id: string;
        };
        Update: {
          activity_id?: string;
          muted_at?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'activity_mutes_activity_id_user_id_fkey';
            columns: ['activity_id', 'user_id'];
            isOneToOne: true;
            referencedRelation: 'rsvps';
            referencedColumns: ['activity_id', 'user_id'];
          },
        ];
      };
      activity_private_details: {
        Row: {
          activity_id: string;
          details: string;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          activity_id: string;
          details: string;
          updated_at?: string;
        };
        Update: {
          activity_id?: string;
          details?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'activity_private_details_activity_id_fkey';
            columns: ['activity_id'];
            isOneToOne: true;
            referencedRelation: 'activities';
            referencedColumns: ['id'];
          },
        ];
      };
      activity_series: {
        Row: {
          capacity: number | null;
          category_id: string;
          cost_note: string | null;
          created_at: string;
          description: string | null;
          duration: string | null;
          freq: string;
          generated_through: string;
          group_id: string | null;
          guests_allowed: boolean;
          id: string;
          idempotency_key: string | null;
          location_name: string;
          max_guests_per_rsvp: number;
          organizer_id: string | null;
          start_date: string;
          start_time: string;
          tag_ids: string[];
          timezone: string;
          title: string;
          until_date: string | null;
          visibility: string;
        };
        ComputedFields: never;
        Insert: {
          capacity?: number | null;
          category_id: string;
          cost_note?: string | null;
          created_at?: string;
          description?: string | null;
          duration?: string | null;
          freq: string;
          generated_through: string;
          group_id?: string | null;
          guests_allowed?: boolean;
          id?: string;
          idempotency_key?: string | null;
          location_name: string;
          max_guests_per_rsvp?: number;
          organizer_id?: string | null;
          start_date: string;
          start_time: string;
          tag_ids?: string[];
          timezone?: string;
          title: string;
          until_date?: string | null;
          visibility?: string;
        };
        Update: {
          capacity?: number | null;
          category_id?: string;
          cost_note?: string | null;
          created_at?: string;
          description?: string | null;
          duration?: string | null;
          freq?: string;
          generated_through?: string;
          group_id?: string | null;
          guests_allowed?: boolean;
          id?: string;
          idempotency_key?: string | null;
          location_name?: string;
          max_guests_per_rsvp?: number;
          organizer_id?: string | null;
          start_date?: string;
          start_time?: string;
          tag_ids?: string[];
          timezone?: string;
          title?: string;
          until_date?: string | null;
          visibility?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'activity_series_category_id_fkey';
            columns: ['category_id'];
            isOneToOne: false;
            referencedRelation: 'categories';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'activity_series_group_id_fkey';
            columns: ['group_id'];
            isOneToOne: false;
            referencedRelation: 'groups';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'activity_series_organizer_id_fkey';
            columns: ['organizer_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      activity_tags: {
        Row: {
          activity_id: string;
          tag_id: string;
        };
        ComputedFields: never;
        Insert: {
          activity_id: string;
          tag_id: string;
        };
        Update: {
          activity_id?: string;
          tag_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'activity_tags_activity_id_fkey';
            columns: ['activity_id'];
            isOneToOne: false;
            referencedRelation: 'activities';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'activity_tags_tag_id_fkey';
            columns: ['tag_id'];
            isOneToOne: false;
            referencedRelation: 'tags';
            referencedColumns: ['id'];
          },
        ];
      };
      activity_updates: {
        Row: {
          activity_id: string | null;
          author_id: string | null;
          body: string;
          created_at: string;
          group_id: string | null;
          hidden_at: string | null;
          hidden_by: string | null;
          hidden_reason: string | null;
          id: string;
          idempotency_key: string | null;
        };
        ComputedFields: never;
        Insert: {
          activity_id?: string | null;
          author_id?: string | null;
          body: string;
          created_at?: string;
          group_id?: string | null;
          hidden_at?: string | null;
          hidden_by?: string | null;
          hidden_reason?: string | null;
          id?: string;
          idempotency_key?: string | null;
        };
        Update: {
          activity_id?: string | null;
          author_id?: string | null;
          body?: string;
          created_at?: string;
          group_id?: string | null;
          hidden_at?: string | null;
          hidden_by?: string | null;
          hidden_reason?: string | null;
          id?: string;
          idempotency_key?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: 'activity_updates_activity_id_fkey';
            columns: ['activity_id'];
            isOneToOne: false;
            referencedRelation: 'activities';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'activity_updates_author_id_fkey';
            columns: ['author_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'activity_updates_group_id_fkey';
            columns: ['group_id'];
            isOneToOne: false;
            referencedRelation: 'groups';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'activity_updates_hidden_by_fkey';
            columns: ['hidden_by'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      calendar_feed_requests: {
        Row: {
          hour: string;
          requests: number;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          hour: string;
          requests?: number;
          user_id: string;
        };
        Update: {
          hour?: string;
          requests?: number;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'calendar_feed_requests_user_id_fkey';
            columns: ['user_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      calendar_feeds: {
        Row: {
          created_at: string;
          token_hash: string;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          token_hash: string;
          user_id: string;
        };
        Update: {
          created_at?: string;
          token_hash?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'calendar_feeds_user_id_fkey';
            columns: ['user_id'];
            isOneToOne: true;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      categories: {
        Row: {
          color_token: string;
          created_at: string;
          icon: string;
          id: string;
          is_active: boolean;
          name: string;
          sort_order: number;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          color_token: string;
          created_at?: string;
          icon: string;
          id: string;
          is_active?: boolean;
          name: string;
          sort_order: number;
          updated_at?: string;
        };
        Update: {
          color_token?: string;
          created_at?: string;
          icon?: string;
          id?: string;
          is_active?: boolean;
          name?: string;
          sort_order?: number;
          updated_at?: string;
        };
        Relationships: [];
      };
      group_members: {
        Row: {
          group_id: string;
          joined_at: string;
          role: string;
          status: string;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          group_id: string;
          joined_at?: string;
          role?: string;
          status?: string;
          user_id: string;
        };
        Update: {
          group_id?: string;
          joined_at?: string;
          role?: string;
          status?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'group_members_group_id_fkey';
            columns: ['group_id'];
            isOneToOne: false;
            referencedRelation: 'groups';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'group_members_user_id_fkey';
            columns: ['user_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      groups: {
        Row: {
          archived_at: string | null;
          category_id: string;
          created_at: string;
          description: string | null;
          hidden_at: string | null;
          id: string;
          idempotency_key: string | null;
          join_policy: string;
          kind: string;
          name: string;
          owner_id: string | null;
          slug: string;
          updated_at: string;
          member_count: number | null;
          my_membership: string | null;
        };
        ComputedFields: 'member_count' | 'my_membership';
        Insert: {
          archived_at?: string | null;
          category_id: string;
          created_at?: string;
          description?: string | null;
          hidden_at?: string | null;
          id?: string;
          idempotency_key?: string | null;
          join_policy?: string;
          kind?: string;
          name: string;
          owner_id?: string | null;
          slug: string;
          updated_at?: string;
        };
        Update: {
          archived_at?: string | null;
          category_id?: string;
          created_at?: string;
          description?: string | null;
          hidden_at?: string | null;
          id?: string;
          idempotency_key?: string | null;
          join_policy?: string;
          kind?: string;
          name?: string;
          owner_id?: string | null;
          slug?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'groups_category_id_fkey';
            columns: ['category_id'];
            isOneToOne: false;
            referencedRelation: 'categories';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'groups_owner_id_fkey';
            columns: ['owner_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      notification_preferences: {
        Row: {
          channel: string;
          enabled: boolean;
          type: string;
          updated_at: string;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          channel?: string;
          enabled?: boolean;
          type: string;
          updated_at?: string;
          user_id: string;
        };
        Update: {
          channel?: string;
          enabled?: boolean;
          type?: string;
          updated_at?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'notification_preferences_user_id_fkey';
            columns: ['user_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      notifications: {
        Row: {
          activity_id: string | null;
          actor_id: string | null;
          created_at: string;
          dedupe_key: string | null;
          group_id: string | null;
          id: string;
          payload: NonNullable<Json>;
          read_at: string | null;
          recipient_id: string;
          type: string;
        };
        ComputedFields: never;
        Insert: {
          activity_id?: string | null;
          actor_id?: string | null;
          created_at?: string;
          dedupe_key?: string | null;
          group_id?: string | null;
          id?: string;
          payload?: NonNullable<Json>;
          read_at?: string | null;
          recipient_id: string;
          type: string;
        };
        Update: {
          activity_id?: string | null;
          actor_id?: string | null;
          created_at?: string;
          dedupe_key?: string | null;
          group_id?: string | null;
          id?: string;
          payload?: NonNullable<Json>;
          read_at?: string | null;
          recipient_id?: string;
          type?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'notifications_activity_id_fkey';
            columns: ['activity_id'];
            isOneToOne: false;
            referencedRelation: 'activities';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'notifications_actor_id_fkey';
            columns: ['actor_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'notifications_group_id_fkey';
            columns: ['group_id'];
            isOneToOne: false;
            referencedRelation: 'groups';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'notifications_recipient_id_fkey';
            columns: ['recipient_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      profile_private: {
        Row: {
          created_at: string;
          email: string;
          email_visible: boolean;
          faculty_type: string | null;
          last_seen_at: string | null;
          previous_visit_at: string | null;
          updated_at: string;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          email: string;
          email_visible?: boolean;
          faculty_type?: string | null;
          last_seen_at?: string | null;
          previous_visit_at?: string | null;
          updated_at?: string;
          user_id: string;
        };
        Update: {
          created_at?: string;
          email?: string;
          email_visible?: boolean;
          faculty_type?: string | null;
          last_seen_at?: string | null;
          previous_visit_at?: string | null;
          updated_at?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'profile_private_user_id_fkey';
            columns: ['user_id'];
            isOneToOne: true;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      profiles: {
        Row: {
          avatar_url: string | null;
          bio: string | null;
          created_at: string;
          department: string | null;
          display_name: string;
          guidelines_accepted_at: string | null;
          guidelines_version: number | null;
          id: string;
          interests: string[];
          public_email: string | null;
          role: string;
          status: string;
          timezone: string;
          updated_at: string;
          use_initials: boolean;
        };
        ComputedFields: never;
        Insert: {
          avatar_url?: string | null;
          bio?: string | null;
          created_at?: string;
          department?: string | null;
          display_name: string;
          guidelines_accepted_at?: string | null;
          guidelines_version?: number | null;
          id: string;
          interests?: string[];
          public_email?: string | null;
          role?: string;
          status?: string;
          timezone?: string;
          updated_at?: string;
          use_initials?: boolean;
        };
        Update: {
          avatar_url?: string | null;
          bio?: string | null;
          created_at?: string;
          department?: string | null;
          display_name?: string;
          guidelines_accepted_at?: string | null;
          guidelines_version?: number | null;
          id?: string;
          interests?: string[];
          public_email?: string | null;
          role?: string;
          status?: string;
          timezone?: string;
          updated_at?: string;
          use_initials?: boolean;
        };
        Relationships: [];
      };
      reports: {
        Row: {
          created_at: string;
          id: string;
          note: string | null;
          reason: string;
          reporter_id: string | null;
          resolution_note: string | null;
          resolved_at: string | null;
          resolved_by: string | null;
          status: string;
          target_id: string;
          target_type: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          id?: string;
          note?: string | null;
          reason: string;
          reporter_id?: string | null;
          resolution_note?: string | null;
          resolved_at?: string | null;
          resolved_by?: string | null;
          status?: string;
          target_id: string;
          target_type: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          note?: string | null;
          reason?: string;
          reporter_id?: string | null;
          resolution_note?: string | null;
          resolved_at?: string | null;
          resolved_by?: string | null;
          status?: string;
          target_id?: string;
          target_type?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'reports_reporter_id_fkey';
            columns: ['reporter_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'reports_resolved_by_fkey';
            columns: ['resolved_by'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      rsvps: {
        Row: {
          activity_id: string;
          created_at: string;
          guest_count: number;
          status: string;
          updated_at: string;
          user_id: string;
          waitlisted_at: string | null;
        };
        ComputedFields: never;
        Insert: {
          activity_id: string;
          created_at?: string;
          guest_count?: number;
          status: string;
          updated_at?: string;
          user_id: string;
          waitlisted_at?: string | null;
        };
        Update: {
          activity_id?: string;
          created_at?: string;
          guest_count?: number;
          status?: string;
          updated_at?: string;
          user_id?: string;
          waitlisted_at?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: 'rsvps_activity_id_fkey';
            columns: ['activity_id'];
            isOneToOne: false;
            referencedRelation: 'activities';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'rsvps_user_id_fkey';
            columns: ['user_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      series_subscriptions: {
        Row: {
          created_at: string;
          series_id: string;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          series_id: string;
          user_id: string;
        };
        Update: {
          created_at?: string;
          series_id?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'series_subscriptions_series_id_fkey';
            columns: ['series_id'];
            isOneToOne: false;
            referencedRelation: 'activity_series';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'series_subscriptions_user_id_fkey';
            columns: ['user_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      tags: {
        Row: {
          created_at: string;
          id: string;
          is_active: boolean;
          name: string;
          sort_order: number;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          id: string;
          is_active?: boolean;
          name: string;
          sort_order: number;
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          is_active?: boolean;
          name?: string;
          sort_order?: number;
          updated_at?: string;
        };
        Relationships: [];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      accept_guidelines: {
        Args: { display_name: string; use_initials: boolean; version: number };
        Returns: undefined;
      };
      add_co_organizer: { Args: { activity_id: string; user_id: string }; Returns: undefined };
      announce_activity: { Args: { activity_id: string }; Returns: number };
      approve_group_member: { Args: { group_id: string; user_id: string }; Returns: undefined };
      attendee_names: { Args: { activity_id: string }; Returns: string[] };
      calendar_feed_events: {
        Args: { token_hash: string };
        Returns: {
          description: string;
          ends_at: string;
          id: string;
          location_name: string;
          starts_at: string;
          status: string;
          title: string;
          version: number;
        }[];
      };
      cancel_activity: { Args: { activity_id: string; reason?: string }; Returns: undefined };
      create_activity: {
        Args: {
          capacity?: number;
          category_id: string;
          copied_from_id?: string;
          cost_note?: string;
          description?: string;
          ends_at?: string;
          group_id?: string;
          guests_allowed?: boolean;
          idempotency_key?: string;
          location_name: string;
          max_guests_per_rsvp?: number;
          private_details?: string;
          starts_at: string;
          title: string;
          visibility?: string;
        };
        Returns: string;
      };
      create_group: {
        Args: {
          category_id: string;
          description?: string;
          idempotency_key?: string;
          join_policy?: string;
          name: string;
        };
        Returns: string;
      };
      create_series: {
        Args: {
          capacity?: number;
          category_id: string;
          cost_note?: string;
          description?: string;
          ends_at?: string;
          freq: string;
          group_id?: string;
          guests_allowed?: boolean;
          idempotency_key?: string;
          location_name: string;
          max_guests_per_rsvp?: number;
          private_details?: string;
          starts_at: string;
          tag_ids?: string[];
          title: string;
          until_date?: string;
          visibility?: string;
        };
        Returns: string;
      };
      delete_my_account: { Args: Record<PropertyKey, never>; Returns: undefined };
      dismiss_report: { Args: { reason: string; report_id: string }; Returns: undefined };
      get_feed: {
        Args: {
          after_id?: string;
          after_starts_at?: string;
          category?: string;
          has_spots?: boolean;
          page_size?: number;
          starts_before?: string;
          starts_from?: string;
          tag_ids?: string[];
        };
        Returns: {
          announced_at: string | null;
          cancel_reason: string | null;
          cancelled_at: string | null;
          capacity: number | null;
          category_id: string;
          copied_from_id: string | null;
          cost_note: string | null;
          created_at: string;
          description: string | null;
          ends_at: string | null;
          going_count: number;
          group_id: string | null;
          guest_total: number;
          guests_allowed: boolean;
          has_private_details: boolean;
          hidden_at: string | null;
          hidden_by: string | null;
          hidden_reason: string | null;
          id: string;
          idempotency_key: string | null;
          is_board_activity: boolean;
          location_name: string;
          max_guests_per_rsvp: number;
          maybe_count: number;
          organizer_id: string | null;
          search_doc: unknown;
          series_detached: boolean;
          series_id: string | null;
          starts_at: string;
          status: string;
          time_or_place_changed_at: string | null;
          timezone: string;
          title: string;
          updated_at: string;
          version: number;
          visibility: string;
        }[];
        SetofOptions: {
          from: '*';
          to: 'activities';
          isOneToOne: false;
          isSetofReturn: true;
        };
      };
      get_session_context: {
        Args: Record<PropertyKey, never>;
        Returns: {
          avatar_url: string;
          display_name: string;
          guidelines_ok: boolean;
          role: string;
          status: string;
          unread_count: number;
          use_initials: boolean;
        }[];
      };
      join_group: { Args: { group_id: string }; Returns: string };
      join_series: { Args: { activity_id: string }; Returns: number };
      leave_group: { Args: { group_id: string }; Returns: undefined };
      leave_series: { Args: { activity_id: string }; Returns: number };
      manages_attendees: { Args: { activity_id: string }; Returns: boolean };
      mark_notifications_read: { Args: { ids?: string[] }; Returns: number };
      member_count: {
        Args: {
          g: Omit<
            Database['public']['Tables']['groups']['Row'],
            Database['public']['Tables']['groups']['ComputedFields']
          >;
        };
        Returns: number;
      };
      member_email: { Args: { member_id: string }; Returns: string };
      moderate_cancel_activity: {
        Args: { activity_id: string; reason: string };
        Returns: undefined;
      };
      moderate_hide: { Args: { activity_id: string; reason: string }; Returns: undefined };
      moderate_hide_update: { Args: { reason: string; update_id: string }; Returns: undefined };
      moderate_transfer_activity: {
        Args: { activity_id: string; reason: string; to_user: string };
        Returns: undefined;
      };
      moderate_unhide: { Args: { activity_id: string; reason: string }; Returns: undefined };
      moderate_unhide_update: { Args: { reason: string; update_id: string }; Returns: undefined };
      mute_activity: { Args: { activity_id: string; muted: boolean }; Returns: undefined };
      my_membership: {
        Args: {
          g: Omit<
            Database['public']['Tables']['groups']['Row'],
            Database['public']['Tables']['groups']['ComputedFields']
          >;
        };
        Returns: string;
      };
      my_rsvp: {
        Args: {
          activity: Omit<
            Database['public']['Tables']['activities']['Row'],
            Database['public']['Tables']['activities']['ComputedFields']
          >;
        };
        Returns: string;
      };
      post_activity_update: {
        Args: { activity_id: string; body: string; idempotency_key?: string };
        Returns: string;
      };
      post_group_update: {
        Args: { body: string; group_id: string; idempotency_key?: string };
        Returns: string;
      };
      record_visit: { Args: Record<PropertyKey, never>; Returns: string };
      reinstate_member: { Args: { reason: string; user_id: string }; Returns: undefined };
      remove_attendee: { Args: { activity_id: string; user_id: string }; Returns: undefined };
      remove_co_organizer: { Args: { activity_id: string; user_id: string }; Returns: undefined };
      remove_group_member: { Args: { group_id: string; user_id: string }; Returns: undefined };
      report_content: {
        Args: { note?: string; reason: string; target_id: string; target_type: string };
        Returns: string;
      };
      reset_calendar_feed: { Args: { token_hash: string }; Returns: undefined };
      restore_activity: { Args: { activity_id: string }; Returns: undefined };
      rsvp: { Args: { activity_id: string; guests?: number; status: string }; Returns: number };
      search_activities: {
        Args: {
          after_id?: string;
          after_starts_at?: string;
          category?: string;
          has_spots?: boolean;
          include_past?: boolean;
          page_size?: number;
          q: string;
          starts_before?: string;
          starts_from?: string;
          tag_ids?: string[];
        };
        Returns: {
          announced_at: string | null;
          cancel_reason: string | null;
          cancelled_at: string | null;
          capacity: number | null;
          category_id: string;
          copied_from_id: string | null;
          cost_note: string | null;
          created_at: string;
          description: string | null;
          ends_at: string | null;
          going_count: number;
          group_id: string | null;
          guest_total: number;
          guests_allowed: boolean;
          has_private_details: boolean;
          hidden_at: string | null;
          hidden_by: string | null;
          hidden_reason: string | null;
          id: string;
          idempotency_key: string | null;
          is_board_activity: boolean;
          location_name: string;
          max_guests_per_rsvp: number;
          maybe_count: number;
          organizer_id: string | null;
          search_doc: unknown;
          series_detached: boolean;
          series_id: string | null;
          starts_at: string;
          status: string;
          time_or_place_changed_at: string | null;
          timezone: string;
          title: string;
          updated_at: string;
          version: number;
          visibility: string;
        }[];
        SetofOptions: {
          from: '*';
          to: 'activities';
          isOneToOne: false;
          isSetofReturn: true;
        };
      };
      set_activity_tags: { Args: { activity_id: string; tag_ids: string[] }; Returns: undefined };
      set_board_activity: { Args: { activity_id: string; board: boolean }; Returns: undefined };
      set_email_visibility: { Args: { visible: boolean }; Returns: undefined };
      set_group_role: {
        Args: { group_id: string; role: string; user_id: string };
        Returns: undefined;
      };
      set_notification_preferences: { Args: { off: string[] }; Returns: undefined };
      suspend_member: { Args: { reason: string; user_id: string }; Returns: undefined };
      sync_my_identity: { Args: Record<PropertyKey, never>; Returns: string };
      transfer_group: {
        Args: { group_id: string; reason?: string; user_id: string };
        Returns: undefined;
      };
      update_activity: {
        Args: { activity_id: string; expected_version: number; patch: Json };
        Returns: undefined;
      };
      update_series: {
        Args: { activity_id: string; expected_version: number; patch: Json; tag_ids?: string[] };
        Returns: number;
      };
      waitlist_position: { Args: { activity_id: string }; Returns: number };
    };
    Enums: {
      [_ in never]: never;
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>;

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, 'public'>];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
    ? (DefaultSchema['Tables'] & DefaultSchema['Views'])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    keyof DefaultSchema['Enums'] | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums']
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums'][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema['Enums']
    ? DefaultSchema['Enums'][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    keyof DefaultSchema['CompositeTypes'] | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes']
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes'][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema['CompositeTypes']
    ? DefaultSchema['CompositeTypes'][PublicCompositeTypeNameOrOptions]
    : never;

export const Constants = {
  public: {
    Enums: {},
  },
} as const;
