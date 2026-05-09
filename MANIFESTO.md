# The Notetux++ Manifesto

## Why this exists

I have been a Notepad++ user for as long as I can remember. It is one of those rare pieces of software that simply works — fast, lightweight, extensible, honest. No subscriptions. No telemetry. No bloat. Just a text editor that respects your time and your machine. Don Ho built something genuinely remarkable, and for that he deserves every bit of recognition he has received over the years.

But Notepad++ has always been a Windows application. Exclusively, stubbornly, almost defiantly so. For years — arguably for over a decade — developers on Linux and macOS have asked, politely and repeatedly, for a native port. The answer has always been silence, or a shrug, or a suggestion to use Wine. The community's love for the project was met with indifference toward half the people expressing it.

That indifference is not a crime. Maintainers owe nobody anything. But it does leave a gap, and gaps get filled.

---

## Andrey filled the gap first

Andrey Letov built a native macOS port of Notepad++. He called it *Notepad++ for Mac*. He used the same icon, the same name with a small qualifier, the same spirit. He did this because he loved the project and wanted to bring it to a platform it had never officially reached. He did it in the open, under the same licence that governs the original.

What he received in return was a cease-and-desist.

Don Ho — who has publicly praised the GPL licence as one of the most liberal and open licences in existence, who has spoken warmly about the values of free software — decided that a port, built out of admiration, distributed for free, carrying the project's name to a platform he had never bothered to support himself, was a threat worth fighting legally.

The stated justification was user confusion. The real effect was to punish someone for caring.

I disagree with that decision completely. Not bitterly, not with anger — but clearly and without reservation. The reasoning does not hold up, and the action was disproportionate to any conceivable harm.

---

## The missed opportunity

Here is the thought that lingers:

If the energy spent on legal threats had been spent on a conversation instead, there might today be an official, cross-platform Notepad++ — built collaboratively by the people who love it most. Andrey on macOS. Someone else on Linux. Don Ho steering the vision. The same application, everywhere, maintained by a community rather than a single developer on a single platform.

That did not happen. Instead, the community fragmented precisely because one part of it was pushed away.

Open source works best when it compounds. When contributors build on each other's work, credit each other honestly, and expand the reach of something good rather than contracting it. The Notepad++ ecosystem chose contraction. This project chooses the other path.

---

## Where Notetux++ comes from

Notetux++ is a fork of Andrey's macOS port, rewritten for Linux with GTK3 in C11. It inherits the vendored Scintilla and Lexilla libraries, the XML configuration format, the feature philosophy, and the overall vision of what a serious text editor should feel like on a Unix desktop.

It exists because:

- Linux deserved a native Notepad++-class editor, and waiting for an official one was no longer a reasonable strategy.
- Andrey's work proved it was possible and provided the foundation.
- The values that make Notepad++ worth using — speed, simplicity, respect for the user — are not Windows-specific values. They belong to every platform.

The name Notetux++ is a deliberate step away from the original trademark. Not because the original name is unworthy, but because this project is its own thing now, with its own roadmap, its own community, and its own identity. Tux, the Linux penguin, belongs in the name. The `++` stays, as a nod to where all of this began.

---

## What this project stands for

**Collaboration over litigation.** If you are building something in this space — a port, a plugin, a compatible tool — I want to talk to you, not send you a letter.

**Credit where it is due.** Don Ho built Notepad++. Andrey Letov proved it could live on macOS. Neil Hodgson built Scintilla and Lexilla. This project stands on all of their work and says so plainly.

**Native over emulated.** Wine is a remarkable technical achievement. It is not a substitute for a native application. Linux users deserve software that belongs on their platform, not software that tolerates it.

**Open, always.** Notetux++ is free software. Its source is open. Its future is shaped by the people who use and contribute to it. No exceptions.

---

*— Andrea Coi, 2026*
