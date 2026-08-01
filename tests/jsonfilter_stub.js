'use strict';

let source;
let expression;
for (let index = 2; index < process.argv.length; index += 2) {
	if (process.argv[index] === '-s')
		source = process.argv[index + 1];
	else if (process.argv[index] === '-e')
		expression = process.argv[index + 1];
}

if (source === undefined || expression === undefined)
	process.exit(2);

let value;
try {
	value = JSON.parse(source);
}
catch (_error) {
	process.exit(1);
}

if (expression === '@.station_list') {
	if (!Object.prototype.hasOwnProperty.call(value, 'station_list'))
		process.exit(1);
	process.stdout.write(JSON.stringify(value.station_list) + '\n');
}
else if (expression === '@.station_list[*]') {
	if (!Array.isArray(value.station_list))
		process.exit(1);
	process.stdout.write(value.station_list.map(JSON.stringify).join('\n'));
	if (value.station_list.length)
		process.stdout.write('\n');
}
else if (/^@\.[A-Za-z0-9_]+$/.test(expression)) {
	const key = expression.slice(2);
	if (!value || typeof value !== 'object' || Array.isArray(value) ||
		!Object.prototype.hasOwnProperty.call(value, key) || value[key] === null)
		process.exit(1);
	if (typeof value[key] === 'object')
		process.stdout.write(JSON.stringify(value[key]) + '\n');
	else
		process.stdout.write(String(value[key]) + '\n');
}
else {
	process.exit(2);
}
