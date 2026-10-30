1.0 (2310) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2310), from source commit `f83cf7350b4bb60e4670da8ee77874ea04db1b01` of 2026-10-25. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- Each conversation's secret now moves forward one day at a time. From 3 November the phone keeps only the step from two days back and erases the original secret, so a secret taken from the phone later cannot open earlier days. From 1 November messages carry the day's tag: update both ends to this build before then. Messages, calls and coins work as before.

Security and anonymity
----------------------

- Security: the pipe secret walks by UTC day; from 03.11 every stored form keeps a 249-byte floor (the walk's value at D-2 and the quantities kept for good) with no byte of the original secret. Limits: an archive head already sent to twins and keepers stays until a newer head is written over it; a device clock set forward moves the floor for good. Builds 2309 and earlier do not hear the new tag from 01.11.
