export function buildPgvDisplayRows<T>(rows:T[],minimumRows=6):(T|null)[]{return Array.from({length:Math.max(minimumRows,rows.length)},(_,index)=>rows[index]||null)}
