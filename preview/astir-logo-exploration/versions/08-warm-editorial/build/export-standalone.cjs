// node export-standalone.cjs assets/46-equal-signal.svg /chosen/output.svg
const fs=require('fs'),path=require('path');
const source=path.resolve(process.argv[2]),destination=path.resolve(process.argv[3]);
const result=fs.readFileSync(source,'utf8').replace(/href="([^"#][^"]*\.png)"/g,(all,ref)=>`href="data:image/png;base64,${fs.readFileSync(path.resolve(path.dirname(source),ref)).toString('base64')}"`);
fs.writeFileSync(destination,result);console.log(destination);
