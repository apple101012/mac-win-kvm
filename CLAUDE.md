# mac-win-kvm: instructions for Claude

This repo is a software KVM: a Windows PC's keyboard and mouse control a Mac, built on Deskflow. People often arrive by pasting this repo's URL into Claude and asking to have it explained and installed.

## When someone wants it explained or set up

Load and follow the setup skill: [`.claude/skills/setup-mac-win-kvm/SKILL.md`](.claude/skills/setup-mac-win-kvm/SKILL.md). If skills aren't available, read that file and follow it.

In short:
1. **Explain** it in plain words, at the depth they want. [`docs/HOW-IT-WORKS.md`](docs/HOW-IT-WORKS.md) is the source.
2. **Interview** them about the few real decisions, with a recommended answer for each. Look up facts (IPs, hostnames, OS versions) yourself; don't ask.
3. **Write** `settings.json` from `settings.example.json`.
4. **Install:** Windows first, exchange the trust files, then the Mac, then Windows again.
5. **Guide** them through the steps only they can do: the admin prompt, macOS Accessibility.
6. **Verify** with both `doctor` scripts and the README checklist.

## Ground rules

- **Supported setup:** only Windows → Mac is tested. Don't promise other combinations.
- **Ask first** before installing software, changing firewall or network adapter settings, or triggering an admin prompt. Say what will happen and why.
- **Keep secrets and addresses out of commits.** Never commit `settings.json`, `trust/*.sha256`, private keys or anyone's addresses. They're git-ignored; keep it that way.
- **Settings go through `settings.json`,** not the Deskflow window. Then re-run the install.

## Working on the code

- Python (`kvmconfig`, `kvmlight`) uses the stdlib only. Tests: `python3 -m unittest discover -s tests -t .`
- Swift: `mac/test.sh` (works with just the Command Line Tools). Keep decisions in `KVMCore` (pure, unit-tested) and I/O in `KVMRuntime`.
- Deskflow behaviour we depend on (log lines, settings keys, TLS files, SIGKILL on macOS) is recorded in `docs/adr/0001-*`. Update it if you find otherwise.
