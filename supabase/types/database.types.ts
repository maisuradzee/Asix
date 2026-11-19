export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      asix_bot_sessions: {
        Row: {
          buyin_tetri: number
          cashed_out_at: string | null
          cashout_tetri: number | null
          created_at: string
          id: string
          status: string
          user_id: string
        }
        Insert: {
          buyin_tetri: number
          cashed_out_at?: string | null
          cashout_tetri?: number | null
          created_at?: string
          id?: string
          status?: string
          user_id: string
        }
        Update: {
          buyin_tetri?: number
          cashed_out_at?: string | null
          cashout_tetri?: number | null
          created_at?: string
          id?: string
          status?: string
          user_id?: string
        }
        Relationships: []
      }
      asix_platform_commission_ledger: {
        Row: {
          amount_tetri: number
          cancelled_at: string | null
          commission_rate_bps: number | null
          created_at: string
          deal_id: string
          gross_table_entry_fee_tetri: number | null
          id: number
          player_user_id: string
          recipient_user_id: string
          room_id: string
          settled_at: string | null
          table_commission_tetri: number | null
        }
        Insert: {
          amount_tetri: number
          cancelled_at?: string | null
          commission_rate_bps?: number | null
          created_at?: string
          deal_id: string
          gross_table_entry_fee_tetri?: number | null
          id?: never
          player_user_id: string
          recipient_user_id: string
          room_id: string
          settled_at?: string | null
          table_commission_tetri?: number | null
        }
        Update: {
          amount_tetri?: number
          cancelled_at?: string | null
          commission_rate_bps?: number | null
          created_at?: string
          deal_id?: string
          gross_table_entry_fee_tetri?: number | null
          id?: never
          player_user_id?: string
          recipient_user_id?: string
          room_id?: string
          settled_at?: string | null
          table_commission_tetri?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "asix_platform_commission_ledger_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "qcard_rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      asix_platform_commission_settings: {
        Row: {
          commission_rate_bps: number
          currency: string
          enabled: boolean
          fee_per_player_tetri: number
          id: number
          recipient_user_id: string
          updated_at: string
        }
        Insert: {
          commission_rate_bps?: number
          currency?: string
          enabled?: boolean
          fee_per_player_tetri?: number
          id?: number
          recipient_user_id: string
          updated_at?: string
        }
        Update: {
          commission_rate_bps?: number
          currency?: string
          enabled?: boolean
          fee_per_player_tetri?: number
          id?: number
          recipient_user_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      asix_wallet_transactions: {
        Row: {
          amount_tetri: number
          balance_after_tetri: number
          created_at: string
          description: string
          id: number
          idempotency_key: string
          metadata: Json
          room_id: string | null
          transaction_type: string
          user_id: string
        }
        Insert: {
          amount_tetri: number
          balance_after_tetri: number
          created_at?: string
          description?: string
          id?: never
          idempotency_key: string
          metadata?: Json
          room_id?: string | null
          transaction_type: string
          user_id: string
        }
        Update: {
          amount_tetri?: number
          balance_after_tetri?: number
          created_at?: string
          description?: string
          id?: never
          idempotency_key?: string
          metadata?: Json
          room_id?: string | null
          transaction_type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "asix_wallet_transactions_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "qcard_rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      asix_wallets: {
        Row: {
          balance_tetri: number
          created_at: string
          updated_at: string
          user_id: string
        }
        Insert: {
          balance_tetri?: number
          created_at?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          balance_tetri?: number
          created_at?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      qcard_actions: {
        Row: {
          action_type: string
          actor_user_id: string | null
          actor_user_id_snapshot: string | null
          created_at: string
          expected_version: number
          id: number
          payload: Json
          processed_at: string | null
          result: Json | null
          room_id: string
          status: string
        }
        Insert: {
          action_type: string
          actor_user_id?: string | null
          actor_user_id_snapshot?: string | null
          created_at?: string
          expected_version: number
          id?: never
          payload?: Json
          processed_at?: string | null
          result?: Json | null
          room_id: string
          status?: string
        }
        Update: {
          action_type?: string
          actor_user_id?: string | null
          actor_user_id_snapshot?: string | null
          created_at?: string
          expected_version?: number
          id?: never
          payload?: Json
          processed_at?: string | null
          result?: Json | null
          room_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "qcard_actions_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "qcard_rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      qcard_deal_history: {
        Row: {
          completed_at: string
          deal_number: number
          final_phase: string
          host_user_id: string | null
          id: number
          room_code: string
          room_id: string
          room_name: string
          room_settings: Json
          started_at: string | null
          state_snapshot: Json
          winner_name: string | null
          winner_user_id: string | null
        }
        Insert: {
          completed_at?: string
          deal_number: number
          final_phase: string
          host_user_id?: string | null
          id?: number
          room_code: string
          room_id: string
          room_name: string
          room_settings?: Json
          started_at?: string | null
          state_snapshot: Json
          winner_name?: string | null
          winner_user_id?: string | null
        }
        Update: {
          completed_at?: string
          deal_number?: number
          final_phase?: string
          host_user_id?: string | null
          id?: number
          room_code?: string
          room_id?: string
          room_name?: string
          room_settings?: Json
          started_at?: string | null
          state_snapshot?: Json
          winner_name?: string | null
          winner_user_id?: string | null
        }
        Relationships: []
      }
      qcard_deal_history_players: {
        Row: {
          all_in: boolean
          cards_count: number
          deal_history_id: number
          display_name: string
          folded: boolean
          id: number
          is_winner: boolean
          seat_no: number
          stack_tetri_after_deal: number | null
          user_id: string | null
        }
        Insert: {
          all_in?: boolean
          cards_count?: number
          deal_history_id: number
          display_name: string
          folded?: boolean
          id?: number
          is_winner?: boolean
          seat_no: number
          stack_tetri_after_deal?: number | null
          user_id?: string | null
        }
        Update: {
          all_in?: boolean
          cards_count?: number
          deal_history_id?: number
          display_name?: string
          folded?: boolean
          id?: number
          is_winner?: boolean
          seat_no?: number
          stack_tetri_after_deal?: number | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "qcard_deal_history_players_deal_history_id_fkey"
            columns: ["deal_history_id"]
            isOneToOne: false
            referencedRelation: "qcard_deal_history"
            referencedColumns: ["id"]
          },
        ]
      }
      qcard_game_logic_version: {
        Row: {
          change_note: string
          changed_at: string
          logic_version: number
          singleton_id: number
        }
        Insert: {
          change_note?: string
          changed_at?: string
          logic_version: number
          singleton_id?: number
        }
        Update: {
          change_note?: string
          changed_at?: string
          logic_version?: number
          singleton_id?: number
        }
        Relationships: []
      }
      qcard_game_state: {
        Row: {
          room_id: string
          state: Json
          updated_at: string
          version: number
        }
        Insert: {
          room_id: string
          state?: Json
          updated_at?: string
          version?: number
        }
        Update: {
          room_id?: string
          state?: Json
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "qcard_game_state_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: true
            referencedRelation: "qcard_rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      qcard_money_ledger: {
        Row: {
          amount_tetri: number
          created_at: string
          details: Json
          entry_type: string
          id: number
          reference_action_id: number | null
          reference_action_id_snapshot: number | null
          reversal_of_ledger_id: number | null
          room_id: string | null
          user_id: string | null
          user_id_snapshot: string | null
        }
        Insert: {
          amount_tetri: number
          created_at?: string
          details?: Json
          entry_type: string
          id?: never
          reference_action_id?: number | null
          reference_action_id_snapshot?: number | null
          reversal_of_ledger_id?: number | null
          room_id?: string | null
          user_id?: string | null
          user_id_snapshot?: string | null
        }
        Update: {
          amount_tetri?: number
          created_at?: string
          details?: Json
          entry_type?: string
          id?: never
          reference_action_id?: number | null
          reference_action_id_snapshot?: number | null
          reversal_of_ledger_id?: number | null
          room_id?: string | null
          user_id?: string | null
          user_id_snapshot?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "qcard_money_ledger_reference_action_id_fkey"
            columns: ["reference_action_id"]
            isOneToOne: false
            referencedRelation: "qcard_actions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "qcard_money_ledger_reversal_of_ledger_id_fkey"
            columns: ["reversal_of_ledger_id"]
            isOneToOne: false
            referencedRelation: "qcard_money_ledger"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "qcard_money_ledger_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "qcard_rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      qcard_private_hands: {
        Row: {
          hand: Json
          room_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          hand?: Json
          room_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          hand?: Json
          room_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "qcard_private_hands_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "qcard_rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      qcard_rooms: {
        Row: {
          card_price: number
          cards_per_player: number
          created_at: string
          growth_reserve_tetri: number
          growth_steps: number[]
          host_user_id: string | null
          host_user_id_snapshot: string | null
          id: string
          max_bet: number
          max_players: number
          name: string
          platform_share: number
          prize_share: number
          room_code: string
          server_heartbeat_at: string | null
          status: string
          updated_at: string
        }
        Insert: {
          card_price?: number
          cards_per_player?: number
          created_at?: string
          growth_reserve_tetri?: number
          growth_steps?: number[]
          host_user_id?: string | null
          host_user_id_snapshot?: string | null
          id?: string
          max_bet?: number
          max_players?: number
          name?: string
          platform_share?: number
          prize_share?: number
          room_code: string
          server_heartbeat_at?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          card_price?: number
          cards_per_player?: number
          created_at?: string
          growth_reserve_tetri?: number
          growth_steps?: number[]
          host_user_id?: string | null
          host_user_id_snapshot?: string | null
          id?: string
          max_bet?: number
          max_players?: number
          name?: string
          platform_share?: number
          prize_share?: number
          room_code?: string
          server_heartbeat_at?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      qcard_seats: {
        Row: {
          display_name: string
          entry_set_at: string | null
          entry_stack_tetri: number | null
          id: string
          is_connected: boolean
          is_ready: boolean
          joined_at: string
          last_seen_at: string
          room_id: string
          seat_no: number
          stack_tetri: number | null
          user_id: string
          wallet_cashout_requested: boolean
          wallet_entry_key: string | null
        }
        Insert: {
          display_name: string
          entry_set_at?: string | null
          entry_stack_tetri?: number | null
          id?: string
          is_connected?: boolean
          is_ready?: boolean
          joined_at?: string
          last_seen_at?: string
          room_id: string
          seat_no: number
          stack_tetri?: number | null
          user_id: string
          wallet_cashout_requested?: boolean
          wallet_entry_key?: string | null
        }
        Update: {
          display_name?: string
          entry_set_at?: string | null
          entry_stack_tetri?: number | null
          id?: string
          is_connected?: boolean
          is_ready?: boolean
          joined_at?: string
          last_seen_at?: string
          room_id?: string
          seat_no?: number
          stack_tetri?: number | null
          user_id?: string
          wallet_cashout_requested?: boolean
          wallet_entry_key?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "qcard_seats_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "qcard_rooms"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      qcard_ledger_reconciliation: {
        Row: {
          action_id: number | null
          adjustments_tetri: number | null
          betting_fund_difference_tetri: number | null
          betting_refunds_tetri: number | null
          card_fund_difference_tetri: number | null
          card_purchase_refunds_tetri: number | null
          card_sales_tetri: number | null
          growth_budget_accounted_tetri: number | null
          growth_released_tetri: number | null
          growth_reserve_tetri: number | null
          initial_prize_allocation_tetri: number | null
          main_prize_paid_tetri: number | null
          other_refunds_tetri: number | null
          platform_allocation_tetri: number | null
          player_bets_tetri: number | null
          room_id: string | null
          round_remainder_tetri: number | null
          side_pots_paid_tetri: number | null
          uncalled_refunds_tetri: number | null
          unclaimed_prize_tetri: number | null
        }
        Relationships: [
          {
            foreignKeyName: "qcard_money_ledger_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "qcard_rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      qcard_seat_balance_reconciliation: {
        Row: {
          actual_stack_tetri: number | null
          difference_tetri: number | null
          display_name: string | null
          entry_stack_tetri: number | null
          expected_stack_tetri: number | null
          ledger_entries: number | null
          room_id: string | null
          seat_no: number | null
          user_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "qcard_seats_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "qcard_rooms"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      asix_wallet_cashout_room: { Args: { p_room_id: string }; Returns: Json }
      asix_wallet_credit: {
        Args: {
          p_amount_tetri: number
          p_description?: string
          p_idempotency_key: string
          p_metadata?: Json
          p_user_id: string
        }
        Returns: Json
      }
      asix_wallet_finish_bot_session: {
        Args: { p_amount_tetri: number; p_session_id: string }
        Returns: Json
      }
      asix_wallet_get_balance: { Args: never; Returns: Json }
      asix_wallet_get_transactions: {
        Args: { p_limit?: number }
        Returns: {
          amount_tetri: number
          balance_after_tetri: number
          created_at: string
          description: string
          id: number
          room_id: string
          transaction_type: string
        }[]
      }
      asix_wallet_settle_cashout: {
        Args: { p_room_id: string; p_user_id: string }
        Returns: Json
      }
      asix_wallet_settle_pending_cashouts: {
        Args: { p_room_id: string }
        Returns: number
      }
      asix_wallet_start_bot_session: {
        Args: { p_amount_tetri: number }
        Returns: Json
      }
      qcard_add_contribution: {
        Args: {
          p_amount_tetri: number
          p_contributions: Json
          p_user_id: string
        }
        Returns: Json
      }
      qcard_allocate_side_pots: {
        Args: { p_played_cards: Json; p_side_pots: Json }
        Returns: Json
      }
      qcard_archive_completed_deal: {
        Args: {
          p_host_user_id: string
          p_room_code: string
          p_room_id: string
          p_room_name: string
          p_settings: Json
          p_state: Json
        }
        Returns: number
      }
      qcard_asix_heartbeat_bundle: {
        Args: { p_room_id: string }
        Returns: Json
      }
      qcard_build_side_pots: {
        Args: { p_contributions: Json; p_players: Json }
        Returns: Json
      }
      qcard_calculate_table_funds: {
        Args: { p_player_count: number; p_sales_tetri: number }
        Returns: Json
      }
      qcard_call_due: {
        Args: {
          p_current_bet_tetri: number
          p_player_contribution_tetri: number
        }
        Returns: number
      }
      qcard_call_payment: {
        Args: {
          p_current_bet_tetri: number
          p_player_contribution_tetri: number
          p_stack_tetri: number
        }
        Returns: Json
      }
      qcard_card_beats: {
        Args: { p_candidate: Json; p_target: Json; p_trump: string }
        Returns: boolean
      }
      qcard_create_room: {
        Args: {
          p_card_price?: number
          p_cards_per_player?: number
          p_display_name?: string
          p_max_bet?: number
          p_max_players?: number
          p_name?: string
        }
        Returns: Json
      }
      qcard_create_room_with_wallet: {
        Args: {
          p_amount_tetri?: number
          p_card_price?: number
          p_cards_per_player?: number
          p_display_name?: string
          p_max_bet?: number
          p_max_players?: number
          p_name?: string
        }
        Returns: Json
      }
      qcard_get_asix_snapshot: { Args: { p_room_id: string }; Returns: Json }
      qcard_get_my_deal_history: {
        Args: {
          p_before_id?: number
          p_limit?: number
          p_requester_user_id: string
        }
        Returns: Json
      }
      qcard_is_room_member: { Args: { p_room_id: string }; Returns: boolean }
      qcard_join_permanent_table: {
        Args: { p_display_name?: string }
        Returns: Json
      }
      qcard_join_public_room: {
        Args: {
          p_amount_tetri: number
          p_display_name: string
          p_room_id: string
        }
        Returns: Json
      }
      qcard_join_room: {
        Args: { p_display_name?: string; p_room_code: string }
        Returns: Json
      }
      qcard_join_room_with_wallet: {
        Args: {
          p_amount_tetri?: number
          p_display_name?: string
          p_room_code: string
        }
        Returns: Json
      }
      qcard_list_public_rooms: {
        Args: never
        Returns: {
          card_price: number
          cards_per_player: number
          created_at: string
          max_bet: number
          max_players: number
          min_entry_tetri: number
          name: string
          occupied_players: number
          online_players: number
          room_id: string
          status: string
        }[]
      }
      qcard_process_action: {
        Args: { p_action_id: number; p_actor_user_id: string }
        Returns: Json
      }
      qcard_process_disconnect_timeouts: {
        Args: { p_requester_user_id: string; p_room_id: string }
        Returns: Json
      }
      qcard_process_turn_timeout: {
        Args: { p_requester_user_id: string; p_room_id: string }
        Returns: Json
      }
      qcard_raise_plan: {
        Args: {
          p_current_bet_tetri: number
          p_max_bet_tetri: number
          p_player_contribution_tetri: number
          p_raise_increment_tetri: number
          p_stack_tetri: number
        }
        Returns: Json
      }
      qcard_record_contribution: {
        Args: { p_add_tetri: number; p_contributions: Json; p_user_id: string }
        Returns: Json
      }
      qcard_recover_pending_action: {
        Args: { p_requester_user_id: string; p_room_id: string }
        Returns: Json
      }
      qcard_remove_permanent_player: {
        Args: { p_target_user_id: string }
        Returns: Json
      }
      qcard_server_heartbeat: {
        Args: { p_requester_user_id: string; p_room_id: string }
        Returns: Json
      }
      qcard_set_entry_stack: {
        Args: { p_amount_tetri: number; p_room_id: string }
        Returns: Json
      }
      qcard_set_presence: {
        Args: { p_connected: boolean; p_room_id: string }
        Returns: undefined
      }
      qcard_submit_action: {
        Args: {
          p_action_type: string
          p_expected_version?: number
          p_payload?: Json
          p_room_id: string
        }
        Returns: number
      }
      qcard_submit_process_action: {
        Args: {
          p_action_type: string
          p_expected_version?: number
          p_payload?: Json
          p_room_id: string
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
