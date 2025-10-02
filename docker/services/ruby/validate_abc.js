const abcjs = require('abcjs');
const fs = require('fs');
const code = fs.readFileSync('/tmp/test_abc.txt', 'utf8');

console.log('Testing ABC code:');
console.log(code);
console.log('---');

try {
  const result = abcjs.renderAbc('*', code, { print: true });
  console.log('Result structure:', JSON.stringify(result, null, 2));

  if (result && result[0]) {
    console.log('result[0].lines exists:', !!result[0].lines);
    console.log('result[0].lines:', result[0].lines);
  }

  if (result && result[0] && !result[0].lines) {
    console.log('\nVALIDATION: FAILED - no lines property');
    console.log(JSON.stringify({ success: false, error: 'invalid syntax' }));
  } else {
    console.log('\nVALIDATION: SUCCESS');
    console.log(JSON.stringify({ success: true }));
  }
} catch (err) {
  console.log('\nVALIDATION: EXCEPTION');
  console.log('Error:', err.message);
  console.log(JSON.stringify({ success: false, error: err.message || 'invalid syntax' }));
}
