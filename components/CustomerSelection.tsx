'use client';
import {useEffect,useState} from 'react';
export function CustomerSelectionNotice({message}:{message:string}){const [visible,setVisible]=useState(true);useEffect(()=>{setVisible(true);const timer=setTimeout(()=>setVisible(false),10000);return()=>clearTimeout(timer)},[message]);return visible?<div role="status">{message}</div>:null}
