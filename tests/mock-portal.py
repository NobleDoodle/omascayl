#!/usr/bin/env python3
"""A stand-in xdg-desktop-portal FileChooser for tests/picker.sh.

Owns org.freedesktop.portal.Desktop on the (private) session bus. OpenFile
records its arguments to $MOCK_LOG, then answers on the Request path:
  MOCK_CODE=0 + MOCK_URI  a picked file/folder
  MOCK_CODE=1             cancelled
  MOCK_CODE=2             failed
  MOCK_CODE=never         no answer, until the request is Closed
Request.Close is recorded too.
"""
import json
import os

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

XML = """
<node>
  <interface name="org.freedesktop.portal.FileChooser">
    <method name="OpenFile">
      <arg type="s" direction="in"/><arg type="s" direction="in"/>
      <arg type="a{sv}" direction="in"/><arg type="o" direction="out"/>
    </method>
  </interface>
</node>"""
REQUEST_XML = """
<node><interface name="org.freedesktop.portal.Request"><method name="Close"/></interface></node>"""

log_path = os.environ["MOCK_LOG"]
events = []


def record(event):
    events.append(event)
    with open(log_path, "w") as f:
        json.dump(events, f)


def on_request_call(conn, sender, path, iface, method, params, invocation):
    record({"event": "close", "path": path})
    invocation.return_value(None)


def on_call(conn, sender, path, iface, method, params, invocation):
    parent, title, options = params.unpack()
    token = options.get("handle_token", "t")
    handle = "/org/freedesktop/portal/desktop/request/%s/%s" % (sender.lstrip(":").replace(".", "_"), token)
    folder = options.get("current_folder")
    record({
        "event": "open", "title": title, "parent": parent,
        "directory": options.get("directory", False),
        "filters": options.get("filters"),
        "current_folder": bytes(folder).rstrip(b"\0").decode() if folder else None,
        "handle": handle,
    })
    node = Gio.DBusNodeInfo.new_for_xml(REQUEST_XML)
    conn.register_object(handle, node.interfaces[0], on_request_call, None, None)
    invocation.return_value(GLib.Variant("(o)", (handle,)))

    code = os.environ.get("MOCK_CODE", "0")
    if code == "never":
        return

    def respond():
        results = {}
        if code == "0":
            results["uris"] = GLib.Variant("as", [os.environ["MOCK_URI"]])
        conn.emit_signal(sender, handle, "org.freedesktop.portal.Request", "Response",
                         GLib.Variant("(ua{sv})", (int(code), results)))
        return GLib.SOURCE_REMOVE

    GLib.timeout_add(int(os.environ.get("MOCK_DELAY", "50")), respond)


def on_bus(conn, name):
    node = Gio.DBusNodeInfo.new_for_xml(XML)
    conn.register_object("/org/freedesktop/portal/desktop", node.interfaces[0], on_call, None, None)


Gio.bus_own_name(Gio.BusType.SESSION, "org.freedesktop.portal.Desktop",
                 Gio.BusNameOwnerFlags.NONE, on_bus, None, None)
GLib.MainLoop().run()
