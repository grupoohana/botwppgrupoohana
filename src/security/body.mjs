export async function jsonBody(request,max=16000) {
 if(Number(request.headers.get('content-length'))>max)throw new Error('Solicitud demasiado grande');
 let length=0;const chunks=[];
 if(request.body)for await(const chunk of request.body){length+=chunk.length;if(length>max)throw new Error('Solicitud demasiado grande');chunks.push(Buffer.from(chunk));}
 return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}
