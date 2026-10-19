const WEEKDAYS = ['SUNDAY', 'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY'];
const MONTHS = ['JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'];
const WEEKDAYS_CN = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
const pad = value => String(value).padStart(2, '0');

export function phaseForHour(hour) {
  if (hour >= 6 && hour < 12) return 'morning';
  if (hour >= 12 && hour < 18) return 'day';
  if (hour >= 18 && hour < 21) return 'evening';
  return 'night';
}

export function clockText(date) {
  return {
    weekday: WEEKDAYS[date.getDay()],
    day: pad(date.getDate()),
    month: MONTHS[date.getMonth()],
    time: `${pad(date.getHours())}:${pad(date.getMinutes())}`,
    date: `${date.getMonth() + 1}月${date.getDate()}日 ${WEEKDAYS_CN[date.getDay()]}`,
  };
}

export function msUntilNextMinute(date) {
  return 60000 - date.getSeconds() * 1000 - date.getMilliseconds();
}

export default {
  name: 'clock',
  css: 'clock.css',
  mount(host, { store }) {
    const doc = host.ownerDocument;
    const win = doc.defaultView;
    host.setAttribute('aria-label', '日期');
    const fields = {};
    for (const key of ['weekday', 'day', 'month', 'time', 'rule', 'date']) {
      const element = doc.createElement('div');
      element.className = `clock-${key}`;
      fields[key] = element;
      host.append(element);
    }

    let timer;
    let disposed = false;
    const update = () => {
      if (disposed) return;
      win.clearTimeout(timer);
      const date = new win.Date();
      for (const [key, text] of Object.entries(clockText(date))) fields[key].textContent = text;
      store.set({
        // Subtract elapsed seconds rather than rebuilding local time across a DST fold.
        now: date.getTime() - date.getSeconds() * 1000 - date.getMilliseconds(),
        phase: phaseForHour(date.getHours()),
      });
      timer = win.setTimeout(update, msUntilNextMinute(new win.Date()) + 50);
    };
    const onVisibilityChange = () => {
      if (doc.visibilityState === 'visible') update();
    };
    doc.addEventListener('visibilitychange', onVisibilityChange);
    update();
    return () => {
      disposed = true;
      win.clearTimeout(timer);
      doc.removeEventListener('visibilitychange', onVisibilityChange);
    };
  },
};
