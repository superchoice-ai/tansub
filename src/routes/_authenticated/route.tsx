import { createFileRoute, redirect, Outlet } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import {
  allowBusinessMutations,
  blockBusinessMutations,
  waitForPendingBusinessMutations,
} from "@/lib/active-session";
import { AppLayout } from "@/components/AppLayout";

export const Route = createFileRoute("/_authenticated")({
  ssr: false,
  beforeLoad: async () => {
    const { data, error } = await supabase.auth.getUser();
    if (error || !data.user) throw redirect({ to: "/auth" });

    const { data: active, error: activeError } = await supabase.rpc("is_current_user_active");
    if (activeError || active !== true) {
      blockBusinessMutations();
      await waitForPendingBusinessMutations();
      await supabase.auth.signOut();
      throw redirect({ to: "/auth", search: { inactive: "1" } });
    }

    allowBusinessMutations();
    return { user: data.user };
  },
  component: () => (
    <AppLayout>
      <Outlet />
    </AppLayout>
  ),
});
