// Materialize picker-backed files before resetting the input or doing network work.
// Android/cloud providers may revoke or change the underlying file reference.
export async function prepareTripFile(file:Pick<File,'size'|'name'|'arrayBuffer'>){
 if(file.size<=0||file.size>10485760)throw Error('Выберите файл размером до 10 МБ');
 let bytes:ArrayBuffer;
 try{bytes=await file.arrayBuffer()}catch{throw Error('Не удалось прочитать выбранный файл. Сохраните его на устройство и выберите повторно')}
 if(bytes.byteLength!==file.size)throw Error('Файл изменился во время чтения. Выберите его повторно');
 return {name:file.name,blob:new Blob([bytes],{type:'application/octet-stream'})};
}
