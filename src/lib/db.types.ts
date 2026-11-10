export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Database = {
  public: {
    Tables: {
      activities: {
        Row: {
          cancel_reason: string | null;
          cancelled_at: string | null;
          capacity: number | null;
          category_id: string;
          cost_note: string | null;
          created_at: string;
          description: string | null;
          ends_at: string | null;
          going_count: number;
          guest_total: number;
          guests_allowed: boolean;
          hidden_at: string | null;
          hidden_by: string | null;
          hidden_reason: string | null;
          id: string;
          idempotency_key: string | null;
          location_name: string;
          max_guests_per_rsvp: number;
          maybe_count: number;
          organizer_id: string | null;
          search_doc: unknown;
          starts_at: string;
          status: string;
          time_or_place_changed_at: string | null;
          timezone: string;
          title: string;
          updated_at: string;
          version: number;
          my_rsvp: string | null;
        };
        ComputedFields: 'my_rsvp';
        Insert: {
          cancel_reason?: string | null;
          cancelled_at?: string | null;
          capacity?: number | null;
          category_id: string;
          cost_note?: string | null;
          created_at?: string;
          description?: string | null;
          ends_at?: string | null;
          going_count?: number;
          guest_total?: number;
          guests_allowed?: boolean;
          hidden_at?: string | null;
          hidden_by?: string | null;
          hidden_reason?: string | null;
          id?: string;
          idempotency_key?: string | null;
          location_name: string;
          max_guests_per_rsvp?: number;
          maybe_count?: number;
          organizer_id?: string | null;
          search_doc?: never;
          starts_at: string;
          status?: string;
          time_or_place_changed_at?: string | null;
          timezone?: string;
          title: string;
          updated_at?: string;
          version?: number;
        };
        Update: {
          cancel_reason?: string | null;
          cancelled_at?: string | null;
          capacity?: number | null;
          category_id?: string;
          cost_note?: string | null;
          created_at?: string;
          description?: string | null;
          ends_at?: string | null;
          going_count?: number;
          guest_total?: number;
          guests_allowed?: boolean;
          hidden_at?: string | null;
          hidden_by?: string | null;
          hidden_reason?: string | null;
          id?: string;
          idempotency_key?: string | null;
          location_name?: string;
          max_guests_per_rsvp?: number;
          maybe_count?: number;
          organizer_id?: string | null;
          search_doc?: never;
          starts_at?: string;
          status?: string;
          time_or_place_changed_at?: string | null;
          timezone?: string;
          title?: string;
          updated_at?: string;
          version?: number;
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
      notifications: {
        Row: {
          activity_id: string | null;
          actor_id: string | null;
          created_at: string;
          dedupe_key: string | null;
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
          updated_at?: string;
          user_id: string;
        };
        Update: {
          created_at?: string;
          email?: string;
          email_visible?: boolean;
          faculty_type?: string | null;
          last_seen_at?: string | null;
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
        };
        ComputedFields: never;
        Insert: {
          activity_id: string;
          created_at?: string;
          guest_count?: number;
          status: string;
          updated_at?: string;
          user_id: string;
        };
        Update: {
          activity_id?: string;
          created_at?: string;
          guest_count?: number;
          status?: string;
          updated_at?: string;
          user_id?: string;
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
      cancel_activity: { Args: { activity_id: string; reason?: string }; Returns: undefined };
      create_activity: {
        Args: {
          capacity?: number;
          category_id: string;
          cost_note?: string;
          description?: string;
          ends_at?: string;
          guests_allowed?: boolean;
          idempotency_key?: string;
          location_name: string;
          max_guests_per_rsvp?: number;
          starts_at: string;
          title: string;
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
          cancel_reason: string | null;
          cancelled_at: string | null;
          capacity: number | null;
          category_id: string;
          cost_note: string | null;
          created_at: string;
          description: string | null;
          ends_at: string | null;
          going_count: number;
          guest_total: number;
          guests_allowed: boolean;
          hidden_at: string | null;
          hidden_by: string | null;
          hidden_reason: string | null;
          id: string;
          idempotency_key: string | null;
          location_name: string;
          max_guests_per_rsvp: number;
          maybe_count: number;
          organizer_id: string | null;
          search_doc: unknown;
          starts_at: string;
          status: string;
          time_or_place_changed_at: string | null;
          timezone: string;
          title: string;
          updated_at: string;
          version: number;
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
      mark_notifications_read: { Args: { ids?: string[] }; Returns: number };
      member_email: { Args: { member_id: string }; Returns: string };
      moderate_cancel_activity: {
        Args: { activity_id: string; reason: string };
        Returns: undefined;
      };
      moderate_hide: { Args: { activity_id: string; reason: string }; Returns: undefined };
      moderate_transfer_activity: {
        Args: { activity_id: string; reason: string; to_user: string };
        Returns: undefined;
      };
      moderate_unhide: { Args: { activity_id: string; reason: string }; Returns: undefined };
      mute_activity: { Args: { activity_id: string; muted: boolean }; Returns: undefined };
      my_rsvp: {
        Args: {
          activity: Omit<
            Database['public']['Tables']['activities']['Row'],
            Database['public']['Tables']['activities']['ComputedFields']
          >;
        };
        Returns: string;
      };
      reinstate_member: { Args: { reason: string; user_id: string }; Returns: undefined };
      report_content: {
        Args: { note?: string; reason: string; target_id: string; target_type: string };
        Returns: string;
      };
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
          cancel_reason: string | null;
          cancelled_at: string | null;
          capacity: number | null;
          category_id: string;
          cost_note: string | null;
          created_at: string;
          description: string | null;
          ends_at: string | null;
          going_count: number;
          guest_total: number;
          guests_allowed: boolean;
          hidden_at: string | null;
          hidden_by: string | null;
          hidden_reason: string | null;
          id: string;
          idempotency_key: string | null;
          location_name: string;
          max_guests_per_rsvp: number;
          maybe_count: number;
          organizer_id: string | null;
          search_doc: unknown;
          starts_at: string;
          status: string;
          time_or_place_changed_at: string | null;
          timezone: string;
          title: string;
          updated_at: string;
          version: number;
        }[];
        SetofOptions: {
          from: '*';
          to: 'activities';
          isOneToOne: false;
          isSetofReturn: true;
        };
      };
      set_activity_tags: { Args: { activity_id: string; tag_ids: string[] }; Returns: undefined };
      set_email_visibility: { Args: { visible: boolean }; Returns: undefined };
      suspend_member: { Args: { reason: string; user_id: string }; Returns: undefined };
      sync_my_identity: { Args: Record<PropertyKey, never>; Returns: string };
      update_activity: {
        Args: { activity_id: string; expected_version: number; patch: Json };
        Returns: undefined;
      };
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
