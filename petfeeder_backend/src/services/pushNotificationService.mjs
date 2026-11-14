import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {cert, getApps, initializeApp} from 'firebase-admin/app';
import {getMessaging} from 'firebase-admin/messaging';

const registrationId=(deviceId,installationId)=>createHash('sha256')
  .update(`${deviceId}:${installationId}`).digest('hex');

export class PushNotificationService {
  constructor(store,{
    serviceAccountJson=process.env.FIREBASE_SERVICE_ACCOUNT_JSON,
    serviceAccountFile=process.env.FIREBASE_SERVICE_ACCOUNT_FILE,
  }={}) {
    this.store=store;
    this.messaging=null;
    if(!serviceAccountJson&&!serviceAccountFile)return;
    try {
      const serviceAccount=JSON.parse(serviceAccountJson||readFileSync(
        resolve(process.cwd(),serviceAccountFile),'utf8'));
      const app=getApps().find(item=>item.name==='petfeeder-push')||initializeApp({
        credential:cert(serviceAccount),projectId:serviceAccount.project_id,
      },'petfeeder-push');
      this.messaging=getMessaging(app);
    } catch(error) {
      console.error('[FCM] Không khởi tạo được Firebase Admin; thông báo đẩy đang tắt:',error.message);
    }
  }

  get enabled(){return this.messaging!==null;}

  async register({fid,deviceId,installationId,platform}) {
    const id=registrationId(deviceId,installationId);
    await this.store.put('push_registrations',id,{
      fid,device_id:deviceId,installation_id:installationId,platform,enabled:true,
      registered_at:new Date().toISOString(),
    });
    return {registered:true,push_enabled:this.enabled};
  }

  async unregister({deviceId,installationId}) {
    const id=registrationId(deviceId,installationId);
    const old=await this.store.get('push_registrations',id);
    if(old)await this.store.put('push_registrations',id,{...old,enabled:false,unregistered_at:new Date().toISOString()});
    return {registered:false};
  }

  async sendPowerRecovery(event) {
    if(!this.messaging)return {sent:0,skipped:true};
    const registrations=(await this.store.all('push_registrations'))
      .filter(row=>row.enabled===true&&row.device_id===event.device_id&&typeof row.fid==='string');
    if(!registrations.length)return {sent:0};
    let sent=0;
    for(let start=0;start<registrations.length;start+=500) {
      const batch=registrations.slice(start,start+500);
      const response=await this.messaging.sendEachForMulticast({
        fids:batch.map(row=>row.fid),
        notification:{
          title:'PetFeeder cần bạn kiểm tra',
          body:'Phiên cho ăn bị gián đoạn do mất điện quá 1 giờ. Mở App để xem cân và xác nhận cấp lại phần còn thiếu.',
        },
        data:{
          type:'POWER_OUTAGE_RETRY_REQUIRED',
          device_id:event.device_id,
          command_id:event.command_id||'',
          event_id:event.event_id,
        },
        android:{
          priority:'high',
          notification:{channelId:'petfeeder_alerts',sound:'default'},
        },
        apns:{payload:{aps:{sound:'default'}},headers:{'apns-priority':'10'}},
      });
      sent+=response.successCount;
      for(let index=0;index<response.responses.length;index++) {
        const result=response.responses[index];
        const code=result.error?.code||'';
        if(!result.success&&[
          'messaging/installation-id-not-registered',
        ].includes(code)) {
          const row=batch[index];
          await this.unregister({deviceId:row.device_id,installationId:row.installation_id});
        }
      }
    }
    return {sent};
  }
}
