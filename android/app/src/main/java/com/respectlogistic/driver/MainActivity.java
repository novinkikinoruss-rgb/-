package com.respectlogistic.driver;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.provider.MediaStore;
import android.view.View;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import androidx.core.content.FileProvider;
import java.io.File;
import java.io.IOException;

/** Thin Android client. Driver authorisation and permissions stay on the CRM server. */
public final class MainActivity extends Activity {
 private WebView web;
 private ValueCallback<Uri[]> upload;
 private Uri cameraUri;
 private File cameraFile;
 private static final String HOST="respectlogistic.onrender.com";
 private static final int PICK_PHOTO=41;
 @Override public void onCreate(Bundle state) {
  super.onCreate(state);
  getWindow().setStatusBarColor(0xffe9ece9);
  getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR);
  web=new WebView(this);setContentView(web);
  WebSettings settings=web.getSettings();settings.setJavaScriptEnabled(true);settings.setDomStorageEnabled(true);
  settings.setAllowFileAccess(false);settings.setAllowContentAccess(false);settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
  settings.setJavaScriptCanOpenWindowsAutomatically(false);settings.setSupportMultipleWindows(false);
  WebView.setWebContentsDebuggingEnabled(false);
  web.setWebViewClient(new WebViewClient(){
   @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){return navigate(request.getUrl());}
  });
  web.setDownloadListener((url,userAgent,disposition,mime,length)->{
   // Blob photos remain available in the CRM; never expose a session in a download URL.
   if(url.startsWith("blob:"))new AlertDialog.Builder(this).setMessage("Фото сохранено в CRM. Для скачивания откройте кабинет в браузере.").setPositiveButton("ОК",null).show();
   else navigate(Uri.parse(url));
  });
  web.setWebChromeClient(new WebChromeClient(){
   @Override public boolean onShowFileChooser(WebView view,ValueCallback<Uri[]> callback,FileChooserParams params){
    if(upload!=null)upload.onReceiveValue(null);upload=callback;
    Intent gallery=new Intent(Intent.ACTION_GET_CONTENT);gallery.setType("image/*");gallery.addCategory(Intent.CATEGORY_OPENABLE);
    Intent chooser=Intent.createChooser(gallery,"Добавить фото");
    try {
     File directory=new File(getCacheDir(),"camera");directory.mkdirs();
     if(cameraFile!=null)cameraFile.delete();cameraFile=File.createTempFile("shift-",".jpg",directory);
     cameraUri=FileProvider.getUriForFile(MainActivity.this,getPackageName()+".photos",cameraFile);
     Intent camera=new Intent(MediaStore.ACTION_IMAGE_CAPTURE);camera.putExtra(MediaStore.EXTRA_OUTPUT,cameraUri);
     camera.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION|Intent.FLAG_GRANT_READ_URI_PERMISSION);
     chooser.putExtra(Intent.EXTRA_INITIAL_INTENTS,new Intent[]{camera});
    }catch(IOException ignored){cameraUri=null;}
    try{startActivityForResult(chooser,PICK_PHOTO);}catch(android.content.ActivityNotFoundException unavailable){upload.onReceiveValue(null);upload=null;}
    return true;
   }
  });
  web.loadUrl("https://"+HOST+"/driver");
 }
 private boolean navigate(Uri uri){
  if("https".equals(uri.getScheme())&&HOST.equals(uri.getHost())&&(uri.getPort()==-1||uri.getPort()==443)&&uri.getUserInfo()==null)return false;
  if(("https".equals(uri.getScheme())&&("yandex.ru".equals(uri.getHost())||"maps.yandex.ru".equals(uri.getHost())))||"tel".equals(uri.getScheme())){
   try{startActivity(new Intent("tel".equals(uri.getScheme())?Intent.ACTION_DIAL:Intent.ACTION_VIEW,uri));}catch(android.content.ActivityNotFoundException ignored){}
  }
  return true;
 }
 @Override protected void onActivityResult(int request,int result,Intent intent){
  super.onActivityResult(request,result,intent);
  if(request!=PICK_PHOTO||upload==null)return;
  Uri[] selected=null;
  if(result==RESULT_OK){Uri uri=intent!=null?intent.getData():null;if(uri==null&&cameraFile!=null&&cameraFile.length()>0)uri=cameraUri;if(uri!=null)selected=new Uri[]{uri};}
  upload.onReceiveValue(selected);upload=null;
 }
 @Override public void onBackPressed(){if(web.canGoBack())web.goBack();else super.onBackPressed();}
 @Override protected void onDestroy(){if(upload!=null)upload.onReceiveValue(null);web.destroy();super.onDestroy();}
}
