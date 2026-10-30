1.0 (2313) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2313), from source commit `7c3624af1f007fbdea9840ccbb215e3c4397bccd` of 2026-10-25. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- Conversations keep their keys in step with the day more reliably: when the phone's clock runs ahead of the network, the first daily step of a conversation's keys waits up to four days for the network to confirm the day, and a conversation met again after a pause stays the same conversation. Messages, calls and coins work as before.

Security and anonymity
----------------------

- This build strengthens security: the daily step that erases a conversation's earlier key is taken by the day the nodes confirm, not by the phone's clock alone, and waits at most four days for that confirmation; a restore from the 24 words takes the later of the two days; erased keys are written to the device's storage again if the first write was refused. Anonymity is unchanged: nothing new leaves the phone.
