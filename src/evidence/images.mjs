import { createHash } from 'node:crypto';
export const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
export async function boundedBytes(response, max = MAX_IMAGE_BYTES) {
  if (Number(response.headers.get('content-length')) > max) { await response.body?.cancel(); throw new Error('La imagen supera el límite de WhatsApp (5 MB).'); }
  const chunks = []; let size = 0;
  for await (const chunk of response.body) { size += chunk.length; if (size > max) throw new Error('La imagen supera el límite de WhatsApp (5 MB).'); chunks.push(Buffer.from(chunk)); }
  return Buffer.concat(chunks);
}
export function validateImage(bytes, declared, expectedHash) {
  if (!bytes.length || bytes.length > MAX_IMAGE_BYTES) throw new Error('Fotografía vacía o demasiado grande para WhatsApp.');
  const png = bytes.length >= 24 && bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])) && bytes.toString('ascii',12,16) === 'IHDR';
  const jpeg = bytes.length >= 12 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255 && bytes[bytes.length-2] === 255 && bytes[bytes.length-1] === 217;
  const mime = png ? 'image/png' : jpeg ? 'image/jpeg' : '';
  if (!mime || declared?.split(';')[0] !== mime) throw new Error('Envía una fotografía JPEG o PNG válida.');
  if (png && (!bytes.readUInt32BE(16) || !bytes.readUInt32BE(20) || bytes.readUInt32BE(16)*bytes.readUInt32BE(20) > 100000000)) throw new Error('Dimensiones de imagen inválidas.');
  if (png) {
    let offset=8,hasData=false,ended=false;
    while(offset+12<=bytes.length){const size=bytes.readUInt32BE(offset);const type=bytes.toString('ascii',offset+4,offset+8);if(offset+12+size>bytes.length)throw new Error('PNG truncado.');if(type==='IDAT'&&size>0)hasData=true;offset+=12+size;if(type==='IEND'){ended=size===0&&offset===bytes.length;break;}}
    if(!hasData||!ended)throw new Error('PNG incompleto.');
  }
  if(jpeg) {
    let offset=2,frame=false,scan=false;
    while(offset<bytes.length-2){if(bytes[offset++]!==255)throw new Error('JPEG inválido.');while(bytes[offset]===255)offset++;const marker=bytes[offset++];if(marker===217)break;if(marker===216||marker>=208&&marker<=215)continue;const length=bytes.readUInt16BE(offset);if(length<2||offset+length>bytes.length)throw new Error('JPEG truncado.');
      if(marker>=192&&marker<=207&&![196,200,204].includes(marker)){if(length<8)throw new Error('JPEG sin dimensiones.');const h=bytes.readUInt16BE(offset+3),w=bytes.readUInt16BE(offset+5);if(!w||!h||w*h>100000000)throw new Error('Dimensiones JPEG inválidas.');frame=true;}
      offset+=length;if(marker===218){scan=true;while(offset<bytes.length-1){if(bytes[offset]===255&&bytes[offset+1]!==0&&!(bytes[offset+1]>=208&&bytes[offset+1]<=215))break;offset+=bytes[offset]===255?2:1;}}
    }
    if(!frame||!scan)throw new Error('JPEG incompleto.');
  }
  const digest = createHash('sha256').update(bytes).digest();
  if (expectedHash && expectedHash !== digest.toString('base64') && expectedHash !== digest.toString('hex')) throw new Error('La integridad de la imagen no coincide.');
  return { bytes, mime, extension: png ? 'png' : 'jpg', hash: digest.toString('hex') };
}
