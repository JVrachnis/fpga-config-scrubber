# Beam-data pipeline (J. Vrachnis, 2018 to 2019; `coverage.py` 2026)

These are the scripts that turned the raw readback images of the CERN 2018 and GSI 2019
heavy-ion campaigns into an upset database and a vocabulary of multi-bit patterns. The design
of the scrubber's second (interleaved) dimension rests on this analysis.

**The beam data is not included** (see the top-level README, "Data"). The scripts are
published so the method can be read and reused. They will not run without the data.

| Script | Stage |
|---|---|
| `find_errors.py` | Golden-diffs every readback image (xc7z020: 10,009 frames x 101 words) with multiple processes. It annotates each flipped bit with the FAR decode, the mask (`.msd`), the essential bit (`.ebd`) and the logic location (`.ll`), producing one CSV row per upset with 22 fields. Paths are set at the top of the file. |
| `projectTools/` | Helpers: binary/ASCII readback parsing, masks, non-essential frames, stopwatch |
| `f_p.py` | Pattern mining. It can screen out frames with more than `max_errors_per_frame = 7` flips (SET/burst screen; `dont_count_set = True` in this copy turns the screen off). It then builds pairwise displacement vectors per capture and keeps vectors seen at least 10 times, takes connected components as patterns, and canonicalises and hashes them. |
| `analyse_distances.py`, `analise_patterns.py` | Displacement-vector and pattern summaries |
| `group_analysis*.py` | Per-column / per-group views used to size the parity groups |
| `visualize_patterns.py` | Renders the pattern atlas |
| `coverage.py` (2026) | Correction-coverage model per interleave depth S. It replays every upset-bearing frame through "ECC only", "parity only" and "both". Run it from the directory that holds `CERN2018/` and `GSI2019/` as `python3 coverage.py --csv`; that produced `campaign/2026-09-03_matrix/coverage_by_S.csv`. |


### The rest of the 2018–2019 working set

Earlier and alternative versions of the same pipeline, kept as they were written (paths and input
file names at the top of each script refer to the original, unpublished data layout).

| Script | Role |
|---|---|
| `binary_from_asciiBinary.py`, `make_reverse_golden.py` | Readback-image decoding: ASCII readback to binary, golden image preparation |
| `Make_Masked_frames.py`, `mk_a_m_n_e.py` | Mask (`.msd`) / essential-bit (`.ebd`) frame lists per test run (`Make_Masked_frames.py` includes a Dec 2018 fix by a fellow student, George) |
| `generate_logic_data.py` | Parses the logic-location file (`.ll`) into per-bit logic data |
| `find_binary_errors.py`, `find_errors_with_less_loops.py` | Earlier and faster variants of `find_errors.py` |
| `find_freerun_erros.py` | Upset extraction for the free-running (non-captured) readback runs |
| `find_errors_test2.py`, `find_errors_test3.py`, `find_errors_for_test2.py` | Per-test-run variants of the extractor |
| `find_paterns.py`, `patern_finder_test.py`, `f_p_test.py`, `aspm.py` | Pattern-finding experiments that preceded `f_p.py` |
| `double_bit_flip.py`, `find_max.py`, `analysis.py` | Quick statistics: adjacent double flips, maxima, golden-zero/one balance |
| `compare.py`, `compare_jsons.py` | Captured vs non-captured readback comparison; result-set diffs |
| `heatmap*.py`, `plotdata*.py`, `pltest.py`, `physical_representation.py` | Early plotting and the column/minor physical-layout view |
| `test.py`, `tt.py` | Scratch checks |

`docs/cernfigs_pro.py` produces the aggregate figures in `docs/figures/` from the same
database (`BEAM_ROOT` and `DOCS_BUILD` environment variables).

Caveat on axis naming: `f_p.py` builds displacement keys as `(delta_frame_index,
delta_bit_in_frame)`. Some thesis figures may label the same tuples the other way round (not yet checked). Read
tuples produced by this code as (frame offset, bit offset).
