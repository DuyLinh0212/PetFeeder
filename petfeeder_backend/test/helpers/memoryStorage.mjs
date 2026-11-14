const clone=value=>value===undefined?undefined:JSON.parse(JSON.stringify(value));

export class MemoryStorage {
  constructor(){this.buckets=new Map();}

  _bucket(name){
    let bucket=this.buckets.get(name);
    if(!bucket){bucket=new Map();this.buckets.set(name,bucket);}
    return bucket;
  }

  get(bucket,id='state'){
    const value=this.buckets.get(bucket)?.get(id);
    return value===undefined?null:clone(value);
  }

  put(bucket,id,body){
    this._bucket(bucket).set(id,clone(body));
    return body;
  }

  putIfAbsent(bucket,id,body){
    const records=this._bucket(bucket);
    if(records.has(id))return false;
    records.set(id,clone(body));
    return true;
  }

  all(bucket){
    return [...(this.buckets.get(bucket)?.values()||[])].reverse().map(clone);
  }

  async transaction(work){
    const snapshot=new Map([...this.buckets].map(([name,records])=>[name,new Map(records)]));
    try{return await work();}
    catch(error){this.buckets=snapshot;throw error;}
  }

  close(){}
}
