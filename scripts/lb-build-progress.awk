#!/usr/bin/awk -f
# Live-build progress display for GreenWayOS build.sh
# Parses real "P:" / "I:" / apt / hook lines from `lb build` (no fake jumps).

function fmt_time(sec,    h, m) {
    if (sec >= 3600) {
        h = int(sec / 3600)
        m = int((sec % 3600) / 60)
        return sprintf("%dh %02dm %02ds", h, m, sec % 60)
    }
    if (sec >= 60) return sprintf("%dm %02ds", int(sec / 60), sec % 60)
    return sprintf("%ds", sec)
}

function get_time(    cmd, t) {
    cmd = "date +%s"
    cmd | getline t
    close(cmd)
    return int(t)
}

function log_line(line,    cmd, ts) {
    cmd = "date +%H:%M:%S"
    cmd | getline ts
    close(cmd)
    print "[" ts "] " line >> logfile
    fflush(logfile)
}

function recalc_pct() {
    # Honest overall %: completed stages + partial current stage
    base = (curr - 1) * stage_weight
    part = intra_pct
    if (part > stage_weight - 1) part = stage_weight - 1
    pct = base + part
    if (pct < 1) pct = 1
    if (pct > 99) pct = 99
}

function advance(n, detail,    now) {
    if (n < 1 || n > num_stages) return
    now = get_time()
    if (n > curr) {
        if (curr >= 1 && !(curr in stage_end_ts))
            stage_end_ts[curr] = now
        curr = n
        if (!(curr in stage_start_ts))
            stage_start_ts[curr] = now
        intra_pct = 0
        pkg_tick = 0
    }
    if (length(detail) > 0)
        subdetail = detail
    recalc_pct()
}

function classify_line(line,    n, d) {
    n = 0; d = ""

    if (line ~ /^P: Begin bootstrapping system/) {
        n = 1; d = line
    } else if (line ~ /^P: End bootstrapping system/) {
        n = 1; d = line
    } else if (line ~ /^P: Begin mounting / || line ~ /^P: Begin running.*chroot_prep/) {
        n = 2; d = line
    } else if (line ~ /^P: Begin installing packages/ || line ~ /^P: Begin installing locales/ ||
               line ~ /^P: Building package lists/ || line ~ /^P: Begin queueing package/) {
        n = 3; d = line
    } else if (line ~ /chroot_linux-image/ || line ~ /^P:.*linux-image/ ||
               line ~ /Installing linux-image/ || line ~ /P: Begin installing kernel/) {
        n = 4; d = line
    } else if (line ~ /^P: Begin executing local hooks/ || line ~ /^P: Begin executing hooks/) {
        n = 5; d = line
    } else if (line ~ /Running hook /) {
        n = 5
        d = line
        sub(/^.*Running hook /, "", d)
        sub(/ \.\.\.$/, "", d)
    } else if (line ~ /^P: Begin building root filesystem image/ ||
               line ~ /mksquashfs/ || line ~ /Parallel mksquashfs/) {
        n = 6; d = line
    } else if (line ~ /^P: Begin building binary\b/ && line !~ /iso image/) {
        n = 7; d = line
    } else if (line ~ /^P: Begin installing bootloaders/) {
        n = 8; d = line
    } else if (line ~ /^P: Begin building binary iso image/) {
        # Only lb's own stage line — do NOT match apt noise like
        # "isohybrid" from syslinux-utils (false jump to stage 9).
        n = 9; d = line
    } else if (line ~ /^P: Begin checksumming binary image/ || line ~ /^P: Begin checksum/) {
        n = 10; d = line
    } else if (line ~ /^Get:[0-9]+ /) {
        n = (curr >= 3 ? curr : 3)
        d = line
        sub(/^Get:[0-9]+ /, "", d)
        if (length(d) > 55) d = substr(d, 1, 52) "..."
    } else if (line ~ /^Unpacking / || line ~ /^Setting up /) {
        # Stay on package stage; never infer ISO from apt package names.
        n = (curr >= 3 && curr <= 5 ? curr : 3)
        d = line
        if (length(d) > 58) d = substr(d, 1, 55) "..."
    } else if ((line ~ /^xorriso / || line ~ /^genisoimage / || line ~ /^isohybrid /) && curr >= 8) {
        n = 9; d = line
        if (length(d) > 58) d = substr(d, 1, 55) "..."
    } else if (line ~ /^P: / || line ~ /^I: /) {
        n = curr
        d = line
        if (length(d) > 58) d = substr(d, 1, 55) "..."
    }

    if (n > 0) advance(n, d)
}

function redraw(    si, now, cur_elapsed, elapsed_s, spin_char, bar_w, bi, filled, bar, trunc, max_w) {
    if (drew_once)
        printf "\r\033[%dA", DISPLAY_LINES

    now = get_time()
    if (curr >= 1 && curr in stage_start_ts)
        cur_elapsed = now - stage_start_ts[curr]
    else
        cur_elapsed = 0

    spin_char = spinner[(idx % 4) + 1]

    printf "\r\033[2K  \033[2m────────────────────────────────────────────────────────────────\033[0m\n"
    printf "\r\033[2K  \033[1;36m%s\033[0m  \033[1;37m%s %d/%d:\033[0m %-28s \033[2m%s\033[0m\n",
        spin_char, l_now, curr, num_stages, stages[curr], fmt_time(cur_elapsed)

    if (length(subdetail) > 0) {
        trunc = subdetail
        max_w = term_cols - 6
        if (length(trunc) > max_w) trunc = substr(trunc, 1, max_w - 1) "…"
        printf "\r\033[2K  \033[2m→\033[0m %s\n", trunc
    } else {
        printf "\r\033[2K\n"
    }

    printf "\r\033[2K  \033[2m────────────────────────────────────────────────────────────────\033[0m\n"

    for (si = 1; si <= num_stages; si++) {
        if (si < curr) {
            elapsed_s = 0
            if (si in stage_start_ts && si in stage_end_ts)
                elapsed_s = stage_end_ts[si] - stage_start_ts[si]
            printf "\r\033[2K  \033[1;32m✓\033[0m %2d. %-38s \033[2m%s\033[0m\n", si, stages[si], fmt_time(elapsed_s)
        } else if (si == curr) {
            printf "\r\033[2K  \033[1;36m▶\033[0m %2d. \033[1;37m%-38s\033[0m \033[2m…\033[0m\n", si, stages[si]
        } else {
            printf "\r\033[2K  \033[2m○\033[0m %2d. %-38s\n", si, stages[si]
        }
    }

    printf "\r\033[2K\n"

    bar_w = 50
    if (bar_w > term_cols - 28) bar_w = term_cols - 28
    if (bar_w < 20) bar_w = 20
    filled = int(bar_w * pct / 100)
    bar = ""
    for (bi = 1; bi <= bar_w; bi++)
        bar = bar ((bi <= filled) ? "█" : "░")
    printf "\r\033[2K  \033[1;32m%s\033[0m %3d%%  \033[2;37m(%d/%d %s)\033[0m\n",
        bar, int(pct), curr, num_stages, l_stages

    if (length(raw_line) > 0) {
        trunc = raw_line
        max_w = term_cols - 4
        if (length(trunc) > max_w) trunc = substr(trunc, 1, max_w - 1) "…"
        printf "\r\033[2K  \033[90m%s\033[0m\n", trunc
    } else {
        printf "\r\033[2K\n"
    }

    drew_once = 1
    fflush("")
}

BEGIN {
    num_stages = 10
    stage_weight = 10   # percent points per stage

    stages[1] = s1;  stages[2] = s2;  stages[3] = s3;  stages[4] = s4
    stages[5] = s5;  stages[6] = s6;  stages[7] = s7;  stages[8] = s8
    stages[9] = s9;  stages[10] = s10

    split("⠋ ⠙ ⠹ ⠸", spinner, " ")

    curr = 1
    pct = 1
    intra_pct = 0
    idx = 0
    events = 0
    pkg_tick = 0
    subdetail = ""
    raw_line = ""
    drew_once = 0

  # sep(1) + header(1) + detail(1) + sep(1) + stages(10) + blank(1) + bar(1) + raw(1) = 17
    DISPLAY_LINES = 17

    stage_start_ts[1] = get_time()

    for (i = 1; i <= DISPLAY_LINES; i++) printf "\r\n"
    printf "\r\033[%dA", DISPLAY_LINES
    fflush("")
}

{
    log_line($0)

    events++
    idx++
    prev_curr = curr

    classify_line($0)

    if ((curr == 3 || curr == 4) && ($0 ~ /^Get:[0-9]+ / || $0 ~ /^Unpacking / || $0 ~ /^Setting up /)) {
        pkg_tick++
        if (pkg_tick % 8 == 0 && intra_pct < stage_weight - 2)
            intra_pct += 1
        recalc_pct()
    }
    if (curr == 5 && $0 ~ /Running hook /) {
        if (intra_pct < stage_weight - 2) intra_pct += 2
        recalc_pct()
    }
    if (curr == 6 && $0 ~ /\[/) {
        if (match($0, /\[[-#>]+\]/)) {
            bar = substr($0, RSTART, RLENGTH)
            gsub(/[^#]/, "", bar)
            blen = length(bar)
            if (blen > 0 && intra_pct < stage_weight - 1)
                intra_pct = int((blen / 40) * (stage_weight - 1))
            recalc_pct()
        }
    }

    if ($0 ~ /^P: / || $0 ~ /^I: / || $0 ~ /^Get:/ || $0 ~ /^Unpacking / ||
        $0 ~ /^Setting up / || $0 ~ /Running hook / || $0 ~ /mksquashfs/) {
        raw_line = $0
    }

    if (events % 2 == 0 || curr != prev_curr || length(subdetail) > 0)
        redraw()
}

END {
    now = get_time()
    if (curr >= 1 && !(curr in stage_end_ts))
        stage_end_ts[curr] = now
    curr = num_stages + 1
    pct = 100

    if (drew_once)
        printf "\r\033[%dA", DISPLAY_LINES

    printf "\r\033[2K  \033[2m────────────────────────────────────────────────────────────────\033[0m\n"
    printf "\r\033[2K  \033[1;32m✔\033[0m  %-50s\n", s_done
    printf "\r\033[2K\n"
    for (si = 1; si <= num_stages; si++) {
        if (si in stage_start_ts && si in stage_end_ts)
            printf "\r\033[2K  \033[1;32m✓\033[0m %2d. %-38s \033[2m%s\033[0m\n",
                si, stages[si], fmt_time(stage_end_ts[si] - stage_start_ts[si])
        else
            printf "\r\033[2K  \033[1;32m✓\033[0m %2d. %-38s\n", si, stages[si]
    }
    printf "\r\033[2K\n"
    printf "\r\033[2K  \033[1;32m██████████████████████████████████████████████████\033[0m 100%%\n"
    fflush("")
}
