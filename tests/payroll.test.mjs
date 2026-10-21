import test from 'node:test';
import assert from 'node:assert/strict';
import {calculatePayroll, DRIVER_RATE_PER_KM} from '../lib/payroll.ts';

test('Одно плечо 100 км × 70 ₽ без удвоения', () => {
  assert.equal(DRIVER_RATE_PER_KM, 70);
  assert.deepEqual(calculatePayroll(100), {base:7000, bonus:0, tax:0, net:7000, totalCost:7000});
});
test('Премия, налоги работодателя и удержание неоплаченного штрафа', () => {
  assert.deepEqual(calculatePayroll(100, 10, 30, 500), {base:7000, bonus:700, tax:2310, net:7200, totalCost:10010});
});
test('Дробные километры и округление до копеек', () => {
  assert.deepEqual(calculatePayroll(1.23, 13, 44), {base:86.1, bonus:11.19, tax:42.81, net:97.29, totalCost:140.1});
});
test('Некорректные входные данные не дают неверное начисление', () => {
  for (const value of [-1, NaN, Infinity]) assert.throws(() => calculatePayroll(value));
  assert.throws(() => calculatePayroll(100, -1));
  assert.throws(() => calculatePayroll(100, 0, -1));
  assert.throws(() => calculatePayroll(100, 0, 0, -1));
});
