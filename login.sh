#!/bin/bash
# hw14 PAM: контроль логина по дням недели
# Суббота/воскресенье — вход только для группы admin, КРОМЕ праздничных дней.
# Праздники берутся из /etc/holidays.d/YYYY (одна дата на строку: MM-DD).

HOLIDAY_FILE="/etc/holidays.d/$(date +%Y)"

is_holiday() {
    [[ -f "$HOLIDAY_FILE" ]] && grep -qx "$(date +%m-%d)" "$HOLIDAY_FILE"
}

is_weekend() {
    local dow=$(date +%a)
    [[ "$dow" == "Sat" || "$dow" == "Sun" ]]
}

if is_weekend && ! is_holiday; then
    if getent group admin | grep -qw "$PAM_USER"; then
        exit 0
    else
        logger -t pam_login_denied "user=$PAM_USER denied: weekend, not in admin group"
        exit 1
    fi
fi

exit 0
