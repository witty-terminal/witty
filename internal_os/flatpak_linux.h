#ifndef WITTY_INTERNAL_OS_FLATPAK_LINUX_H
#define WITTY_INTERNAL_OS_FLATPAK_LINUX_H

#include <gio/gio.h>

/* Keep the Flatpak V bindings distinct from the GTK IPC bindings. */
#define witty_flatpak_bus_get_sync g_bus_get_sync
#define witty_flatpak_dbus_call_sync g_dbus_connection_call_sync

void witty_flatpak_host_command_on_exit(void *bus, void *params, void *user_data);

static void witty_flatpak_host_command_exited(GDBusConnection *bus,
                                              const gchar *sender,
                                              const gchar *path,
                                              const gchar *interface,
                                              const gchar *signal,
                                              GVariant *params,
                                              gpointer user_data)
{
    witty_flatpak_host_command_on_exit(bus, params, user_data);
}

static inline guint witty_flatpak_subscribe_host_command_exited(GDBusConnection *bus,
                                                                 gpointer user_data)
{
    return g_dbus_connection_signal_subscribe(bus, "org.freedesktop.Flatpak",
        "org.freedesktop.Flatpak.Development", "HostCommandExited",
        "/org/freedesktop/Flatpak/Development", NULL, G_DBUS_SIGNAL_FLAGS_NONE,
        witty_flatpak_host_command_exited, user_data, NULL);
}

#endif
