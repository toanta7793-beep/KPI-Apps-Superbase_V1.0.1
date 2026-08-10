"use client";
import { useEffect, useState } from "react";

export function isoToDisplay(iso:string){if(!/^\d{4}-\d{2}-\d{2}$/.test(iso))return "";const [y,m,d]=iso.split("-");return `${d}/${m}/${y}`}
export function displayToIso(text:string){const m=text.trim().match(/^(\d{2})\/(\d{2})\/(\d{4})$/);if(!m)return "";const d=Number(m[1]),mo=Number(m[2]),y=Number(m[3]);const date=new Date(Date.UTC(y,mo-1,d));if(y<1900||y>2200||date.getUTCFullYear()!==y||date.getUTCMonth()!==mo-1||date.getUTCDate()!==d)return "";return `${String(y).padStart(4,"0")}-${String(mo).padStart(2,"0")}-${String(d).padStart(2,"0")}`}
export function maskDateInput(raw:string){const digits=raw.replace(/\D/g,"").slice(0,8);if(digits.length<=2)return digits;if(digits.length<=4)return `${digits.slice(0,2)}/${digits.slice(2)}`;return `${digits.slice(0,2)}/${digits.slice(2,4)}/${digits.slice(4)}`}

export function DateInput({value,onChange,name,required=true,className="form-control"}:{value:string;onChange:(iso:string)=>void;name?:string;required?:boolean;className?:string}){
  const [text,setText]=useState(isoToDisplay(value));
  useEffect(()=>{const timer=window.setTimeout(()=>setText(isoToDisplay(value)),0);return()=>window.clearTimeout(timer)},[value]);
  const complete=text.length===10,invalid=complete&&!displayToIso(text);
  function change(raw:string){const next=maskDateInput(raw);setText(next);onChange(displayToIso(next))}
  return <><input className={`${className}${invalid?" date-invalid":""}`} inputMode="numeric" placeholder="dd/mm/yyyy" aria-label="Ngày theo định dạng dd/mm/yyyy" value={text} onChange={e=>change(e.target.value)} maxLength={10} pattern="\d{2}/\d{2}/\d{4}" aria-invalid={invalid} title={invalid?"Ngày không hợp lệ. Hãy nhập đúng dd/mm/yyyy.":"Nhập ngày theo dd/mm/yyyy"} required={required}/>{name&&<input type="hidden" name={name} value={value}/>}</>;
}
