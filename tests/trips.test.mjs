import test from 'node:test';
import assert from 'node:assert/strict';
import {blankTripFilter,tripVehicleChoices,filterTrips,toggleVisibleSelection,tripPeriod,volumeTotals,csvCell} from '../lib/trips.ts';
const rows=[
 {id:'1',trip_number:'Р-1',trip_date:'2026-10-01',customer_id:'a',site_id:'x',vehicle_id:'v1',loading_address:'Москва',unloading_address:'Север',volume:12.5,unit:'м³'},
 {id:'2',trip_number:'Р-2',trip_date:'2026-10-10',customer_id:'a',site_id:'y',vehicle_id:'v2',loading_address:'Юг',unloading_address:'Север',volume:2,unit:'т'},
 {id:'3',trip_number:'Р-3',trip_date:'2026-10-10',customer_id:'b',site_id:'z',vehicle_id:'v3',loading_address:'Запад',unloading_address:'Центр',volume:7.25,unit:'м³'},
 {id:'4',trip_number:'Без даты',trip_date:null,customer_id:'b',site_id:'z',volume:1,unit:'рейс'}
];
test('vehicle selection separates company and carrier fleets and preserves only the current archived vehicle',()=>{
 const vehicles=[{id:'own',carrier_id:null,is_subcontractor_vehicle:false,archived_at:null},{id:'carrier-a',carrier_id:'a',is_subcontractor_vehicle:true,archived_at:null},{id:'carrier-b',carrier_id:'b',is_subcontractor_vehicle:true,archived_at:null},{id:'archived',carrier_id:null,is_subcontractor_vehicle:false,archived_at:'2026-10-01'}];
 assert.deepEqual(tripVehicleChoices(vehicles,'own','').map(v=>v.id),['own']);
 assert.deepEqual(tripVehicleChoices(vehicles,'contractor','a').map(v=>v.id),['carrier-a']);
 assert.deepEqual(tripVehicleChoices(vehicles,'contractor','').map(v=>v.id),[]);
 assert.deepEqual(tripVehicleChoices(vehicles,'own','','archived').map(v=>v.id),['own','archived']);
 assert.deepEqual(tripVehicleChoices([],'contractor','a'),[]);
});
test('period boundaries customer and object filters compose',()=>{
 assert.deepEqual(filterTrips(rows,{...blankTripFilter,from:'2026-10-01',to:'2026-10-10',customer:'a'}).map(t=>t.id),['1','2']);
 assert.deepEqual(filterTrips(rows,{...blankTripFilter,from:'2026-10-10',to:'2026-10-10',site:'z'}).map(t=>t.id),['3']);
 assert.equal(filterTrips(rows,blankTripFilter).length,4);
});
test('search includes registration plate and addresses case insensitively',()=>{
 assert.deepEqual(filterTrips(rows,{...blankTripFilter,search:'а123аа'},{v1:'А123АА 77'}).map(t=>t.id),['1']);
 assert.deepEqual(filterTrips(rows,{...blankTripFilter,search:'сЕвЕр'}).map(t=>t.id),['1','2']);
});
test('select all visible deduplicates and never toggles hidden rows',()=>{
 assert.deepEqual(toggleVisibleSelection(['hidden','1'],['1','2'],true),['hidden','1','2']);
 assert.deepEqual(toggleVisibleSelection(['hidden','1','2'],['1','2'],false),['hidden']);
});
test('calendar presets are local dates and cross month boundaries',()=>{
 const now=new Date(2026,2,2,23,55);
 assert.deepEqual(tripPeriod('week',now),{from:'2026-02-24',to:'2026-03-02'});
 assert.deepEqual(tripPeriod('month',now),{from:'2026-03-01',to:'2026-03-02'});
 assert.deepEqual(tripPeriod('all',now),{from:'',to:''});
});
test('volume totals never add tonnes to cubic metres',()=>{
 assert.deepEqual(volumeTotals(rows),[{unit:'м³',total:19.75},{unit:'т',total:2},{unit:'рейс',total:1}]);
});
test('CSV escapes quotes and suppresses executable spreadsheet formulas',()=>{
 assert.equal(csvCell('Адрес \"А\"'),'"Адрес ""А"""');
 assert.equal(csvCell('=SUM(A1:A2)'),`"'=SUM(A1:A2)"`);
});

