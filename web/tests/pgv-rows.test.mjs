import test from "node:test";import assert from "node:assert/strict";import {buildPgvDisplayRows} from "../app/pgvRows.ts";
test("PGV keeps a six-row minimum for short weeks",()=>{const rows=buildPgvDisplayRows([{id:1},{id:2}]);assert.equal(rows.length,6);assert.equal(rows.filter(Boolean).length,2)});
test("PGV automatically grows beyond six rows without dropping jobs",()=>{const input=Array.from({length:12},(_,i)=>({id:i+1})),rows=buildPgvDisplayRows(input);assert.equal(rows.length,12);assert.deepEqual(rows,input)});
