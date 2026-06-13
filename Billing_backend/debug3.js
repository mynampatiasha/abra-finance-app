const abbr = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
const fyMonths = [3,4,5,6,7,8,9,10,11,0,1,2];
const currentFYYear = 2026;
const fmt = (n) => Math.round((n || 0) * 100) / 100;

const monthlyMap = {
  "2026-5": { incoming: 0, outgoing: 17385 }
};

let runningBalance = 1245869.62;
const monthlyBreakdown = [];

for (const mIndex of fyMonths) {
  const isNextYear = mIndex < 3;
  const year = currentFYYear + (isNextYear ? 1 : 0);
  const key = `${year}-${mIndex}`;
  
  const incoming = monthlyMap[key]?.incoming || 0;
  const outgoing = monthlyMap[key]?.outgoing || 0;
  runningBalance += (incoming - outgoing);
  
  monthlyBreakdown.push({
    month: abbr[mIndex],
    incoming: fmt(incoming),
    outgoing: fmt(outgoing),
    endingBalance: fmt(runningBalance)
  });
}

console.log(JSON.stringify(monthlyBreakdown, null, 2));
