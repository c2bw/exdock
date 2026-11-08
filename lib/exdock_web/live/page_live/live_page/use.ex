defmodule ExdockWeb.PageLive.LivePage.Use do
  @moduledoc """
  Thin compile-time adapter for LiveViews using the shared page lifecycle.

  Keeping this macro separate prevents changes to lifecycle implementation
  dependencies from forcing every operational page to recompile.
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @live_page_options opts

      @impl true
      def mount(params, session, socket) do
        ExdockWeb.PageLive.LivePage.mount(
          params,
          session,
          socket,
          @live_page_options,
          &bootstrap_page/4,
          &load_page_context/2
        )
      end

      def load_page_context(_params, projections), do: Exdock.ReadModel.page(projections)
      def bootstrap_page(_params, _session, socket, _context), do: socket

      @impl true
      def handle_info(message, socket) do
        ExdockWeb.PageLive.LivePage.handle_info(
          message,
          socket,
          &handle_page_broadcast/2
        )
      end

      def handle_page_broadcast(_message, _socket), do: :unhandled

      @impl true
      def handle_event(event, params, socket) do
        ExdockWeb.PageLive.LivePage.handle_event(
          event,
          params,
          socket,
          &handle_page_event/3
        )
      end

      def handle_page_event(_event, _params, _socket), do: :unhandled

      defoverridable load_page_context: 2,
                     bootstrap_page: 4,
                     handle_page_broadcast: 2,
                     handle_page_event: 3
    end
  end
end
