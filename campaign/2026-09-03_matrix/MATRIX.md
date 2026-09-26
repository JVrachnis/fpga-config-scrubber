| config | LUT | FF | BRAM | WNS ns | pass period | campaign det/corr/PASS of n | latency med/max ms | capacity: k adj2 in one column (dirty of k) | 2 adj2 same subgroup | coverage CERN/GSI |
|---|---|---|---|---|---|---|---|---|---|---|
| S2G64 | 3289 | 3114 | 20 | 0.969 | 16 ms (JTAG-bound) | 149/148/148 of 150 | 5 / 6 | k=1:0, k=2:0, k=3:2* | 2/2 dirty* | 99.45% / 99.46% |
|  | | | | | | fails: 0x40150C rehits=38 drops=3 wd=0; 0x00091B nodet | | | | |
| S2G64_wdoff | 3275 | 3108 | 20 | 0.789 | 16 ms (JTAG-bound) | 149/149/149 of 150 | 5 / 6 | k=1:0, k=2:0, k=3:2* | 2/2 dirty* | 99.45% / 99.46% |
|  | | | | | | fails: 0x00091B nodet | | | | |
| S4G128 | 4063 | 3383 | 37 | 0.611 | 16 ms (JTAG-bound) | 149/149/149 of 150 | 5 / 6 | k=1:0, k=2:0, k=3:0, k=4:0, k=5:2* | 2/2 dirty* | 99.80% / 99.73% |
|  | | | | | | fails: 0x00091B nodet | | | | |
| S4G64 | 4005 | 3339 | 37 | 0.532 | 16 ms (JTAG-bound) | 149/149/149 of 150 | 4 / 6 | k=1:0, k=2:0, k=3:0, k=4:0, k=5:2* | 2/2 dirty* | 99.80% / 99.73% |
|  | | | | | | fails: 0x00091B nodet | | | | |
| S8G64 | None | None | None | None |  |  |  |  |  | 99.87% / 99.79% |

* = handler busy > 50% during the 5 s watch (livelock)
