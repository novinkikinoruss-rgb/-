export const DRIVER_RATE_PER_KM = 70;

export function calculatePayroll(distanceKm: number, bonusPct = 0, taxPct = 0, unpaidFines = 0) {
  for (const value of [distanceKm, bonusPct, taxPct, unpaidFines]) {
    if (!Number.isFinite(value) || value < 0) throw new Error('Расстояние, проценты и штрафы должны быть неотрицательными числами');
  }
  const round = (value: number) => Math.round((value + Number.EPSILON) * 100) / 100;
  const base = round(distanceKm * DRIVER_RATE_PER_KM);
  const bonus = round(base * bonusPct / 100);
  // Налоги работодателя: не уменьшают выплату водителю.
  const tax = round((base + bonus) * taxPct / 100);
  const net = round(base + bonus - unpaidFines);
  return {base, bonus, tax, net, totalCost: round(base + bonus + tax)};
}
