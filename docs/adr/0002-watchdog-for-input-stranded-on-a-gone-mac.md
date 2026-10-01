# 0002 — Watchdog for input stranded on a Mac that has gone away

Status: accepted (Deskflow 1.26.0)

## Context

In a real session the Mac switched Wi-Fi while it had the cursor. Deskflow logged `IPC: client "MacBook" is dead` but never switched back to the PC. That left the PC's keyboard and mouse dead until Deskflow was restarted by hand. The recording is `fixtures/deskflow-1.26.0-stranded.log`.

## Decision

The always-running helper (`kvmlight/helper.py`) also runs a `StrandDetector`.

- **When it fires:** the Mac is reported dead or disconnected while it's the active screen, and no switch back to the PC follows within 3 s.
- **What it does then:** the helper kills and relaunches the Deskflow GUI, which hands input back to Windows. The Mac app reconnects by itself.
- **Not counted as a strand:**
  - a rejected duplicate client disconnecting
  - Deskflow switching back to the PC by itself
  - a server restart
- **Startup:** history replayed when the helper starts never triggers a restart.

**Manual escape hatch:** Ctrl+Alt+Del → Task Manager → end Deskflow.
