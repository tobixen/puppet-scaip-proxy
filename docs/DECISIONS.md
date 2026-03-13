# Design Decisions

## Why a new Puppet module (tobixen-scaip_proxy) rather than trulabs/kamailio or alisio/opensips

Two community modules were evaluated:

### trulabs/kamailio (https://forge.puppet.com/modules/trulabs/kamailio)

Last substantive code commit: 2019. Last release: October 2014 (v0.0.7).  Disqualifying issues:

- Written for Puppet 2.7. Uses `validate_string()`/`validate_bool()` from stdlib which were
  removed in Puppet 6, causing catalog compilation failures on Puppet 7+.
- All subclasses use `inherits` to pull parameters from `params.pp` — a pattern that still
  works but generates deprecation warnings and causes subtle ordering bugs.
- Service resource hardcodes `/etc/init.d/kamailio restart/start/stop` — broken on
  any systemd-based host (all modern Debian/Ubuntu).
- Apt source targets Debian Wheezy (EOL 2018) with a hardcoded GPG key ID that no longer
  matches Kamailio's current signing key.
- The bundled `kamailio.cfg.erb` template targets Kamailio 4.x (EOL). Current release is 6.x.
- No test suite, no CI.
- Estimated remediation effort: 30–40 hours, essentially a rewrite.

### alisio/opensips (https://forge.puppet.com/modules/alisio/opensips)

Last release: September 2019 (v0.6.3). Only supports RedHat/CentOS. No Debian/Ubuntu support,
which rules it out entirely for our deployment target.

OpenSIPS and Kamailio are two quite comparable packages, OpenSIPS is said to have a bit easier configuration language.  Claude suggested to "toss a coin", Perplexity claims that "Kamailio prioritizes stability, compatibility, and conservative feature releases, (...) OpenSIPS emphasizes rapid innovation,".  It's a quite simple usecase, it's ultra-sharp production, so "stability, compatibility and conservative feature releases" sounds better than "rapid innovation".

Kamailio is probably overkill for the stated purpose, but some of the feaures are useful for us - we do need metrics, alarms and readiness probe.

### Decision

Writing a focused, purpose-built module from scratch is faster and produces a better result
than trying to resurrect either community module.  The new module:

- Targets Puppet 7+ (tested against 7 and 8 in CI)
- Follows the same conventions as the other tobixen-* puppet modules
- Is scoped specifically to the SCAIP proxy use case rather than being a general-purpose
  Kamailio module, keeping it simple and auditable for a life-safety deployment
- Ships with a kamailio.cfg tuned for NAT traversal + SIPS upstream (not a generic 900-line
  default config)
- Includes health, readiness, and Prometheus metrics endpoints out of the box
- Named `tobixen-scaip_proxy` to reflect its purpose rather than the underlying software

## Why Kamailio rather than OpenSIPS

Both are production-grade and would work. Kamailio was chosen because:

- Larger community and more third-party documentation/tutorials online
- More modules in the ecosystem (200+ vs ~120)
- Active releases: Kamailio 6.1.1 released March 2026

The differences are marginal for this use case; either would have been fine.

## Why not use Asterisk (already deployed)

Asterisk is a B2BUA (Back-to-Back User Agent), not a SIP proxy. It terminates the SIP
dialog on the internal side and originates a new dialog toward the destination, rewriting
all headers in the process. Risks for SCAIP:

- SCAIP-specific SIP methods (MESSAGE, INFO, NOTIFY carrying alarm data) may not pass
  through transparently — Asterisk only handles what its dialplan and channel drivers
  understand.
- SCAIP requires persistent TLS connections; Asterisk manages its own connection lifecycle
  and does not guarantee this.
- Silent failure mode: if Asterisk drops a SCAIP message because it doesn't recognise a
  SIP construct, the alarm is lost with no indication.

For a life-safety system, a transparent SIP proxy (Kamailio) is the right tool.

## High-availability: anycast with two servers

Two proxy instances behind anycast BGP routing gives active/active HA. Notes:

- Anycast routes consistently per client IP (same BGP path), so a client sticks to one
  node under normal operation.
- On node failure, anycast shifts traffic to the surviving node. Active SIP dialogs will
  drop and clients need to re-REGISTER/re-INVITE — acceptable for alarm devices.
- If seamless failover is needed later, Kamailio's DMQ module can replicate dialog/
  registration state between the two nodes, enabling zero-disruption failover.
  
The anycast setup is not part of this puppet module.

## Configuration split: kamailio.cfg vs Puppet parameters

Rather than templating every Kamailio configuration knob through Puppet, the approach is:

- Puppet manages host-specific values (IP addresses, ports, upstream host, TLS cert paths)
  as class parameters backed by Hiera.
- The routing logic in `kamailio.cfg` is kept in the template and is intentionally not
  parameterised beyond what is needed for the proxy function.
- This keeps the Puppet layer thin and the Kamailio config readable and auditable.
