/*************************************************************************/
/*  java_godot_wrapper.cpp                                               */
/*************************************************************************/
/*                       This file is part of:                           */
/*                           GODOT ENGINE                                */
/*                      https://godotengine.org                          */
/*************************************************************************/
/* Copyright (c) 2007-2022 Juan Linietsky, Ariel Manzur.                 */
/* Copyright (c) 2014-2022 Godot Engine contributors (cf. AUTHORS.md).   */
/*                                                                       */
/* Permission is hereby granted, free of charge, to any person obtaining */
/* a copy of this software and associated documentation files (the       */
/* "Software"), to deal in the Software without restriction, including   */
/* without limitation the rights to use, copy, modify, merge, publish,   */
/* distribute, sublicense, and/or sell copies of the Software, and to    */
/* permit persons to whom the Software is furnished to do so, subject to */
/* the following conditions:                                             */
/*                                                                       */
/* The above copyright notice and this permission notice shall be        */
/* included in all copies or substantial portions of the Software.       */
/*                                                                       */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,       */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF    */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.*/
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY  */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,  */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                */
/*************************************************************************/

#include "java_godot_wrapper.h"

// JNIEnv is only valid within the thread it belongs to, in a multi threading environment
// we can't cache it.
// For Godot we call most access methods from our thread and we thus get a valid JNIEnv
// from get_jni_env(). For one or two we expect to pass the environment

// TODO we could probably create a base class for this...

GodotJavaWrapper::GodotJavaWrapper(JNIEnv *p_env, jobject p_activity, jobject p_godot_instance) {
	godot_instance = p_env->NewGlobalRef(p_godot_instance);
	activity = p_env->NewGlobalRef(p_activity);

	// get info about our Godot class so we can get pointers and stuff...
	godot_class = p_env->FindClass("org/godotengine/godot/Godot");
	if (godot_class) {
		godot_class = (jclass)p_env->NewGlobalRef(godot_class);
	} else {
		// this is a pretty serious fail.. bail... pointers will stay 0
		return;
	}
	activity_class = p_env->FindClass("android/app/Activity");
	if (activity_class) {
		activity_class = (jclass)p_env->NewGlobalRef(activity_class);
	} else {
		// this is a pretty serious fail.. bail... pointers will stay 0
		return;
	}

	// get some Godot method pointers...
	_on_video_init = p_env->GetMethodID(godot_class, "onVideoInit", "()Z");
	_restart = p_env->GetMethodID(godot_class, "restart", "()V");
	_finish = p_env->GetMethodID(godot_class, "forceQuit", "()V");
	_set_keep_screen_on = p_env->GetMethodID(godot_class, "setKeepScreenOn", "(Z)V");
	_alert = p_env->GetMethodID(godot_class, "alert", "(Ljava/lang/String;Ljava/lang/String;)V");
	_get_GLES_version_code = p_env->GetMethodID(godot_class, "getGLESVersionCode", "()I");
	_get_clipboard = p_env->GetMethodID(godot_class, "getClipboard", "()Ljava/lang/String;");
	_set_clipboard = p_env->GetMethodID(godot_class, "setClipboard", "(Ljava/lang/String;)V");
	_has_clipboard = p_env->GetMethodID(godot_class, "hasClipboard", "()Z");
	_request_permission = p_env->GetMethodID(godot_class, "requestPermission", "(Ljava/lang/String;)Z");
	_request_permissions = p_env->GetMethodID(godot_class, "requestPermissions", "()Z");
	_get_granted_permissions = p_env->GetMethodID(godot_class, "getGrantedPermissions", "()[Ljava/lang/String;");
	_init_input_devices = p_env->GetMethodID(godot_class, "initInputDevices", "()V");
	_get_surface = p_env->GetMethodID(godot_class, "getSurface", "()Landroid/view/Surface;");
	_is_activity_resumed = p_env->GetMethodID(godot_class, "isActivityResumed", "()Z");
	_vibrate = p_env->GetMethodID(godot_class, "vibrate", "(I)V");
	_get_input_fallback_mapping = p_env->GetMethodID(godot_class, "getInputFallbackMapping", "()Ljava/lang/String;");
	_on_godot_setup_completed = p_env->GetMethodID(godot_class, "onGodotSetupCompleted", "()V");
	_on_godot_main_loop_started = p_env->GetMethodID(godot_class, "onGodotMainLoopStarted", "()V");
	_create_new_godot_instance = p_env->GetMethodID(godot_class, "createNewGodotInstance", "([Ljava/lang/String;)V");

	// get some Activity method pointers...
	_get_class_loader = p_env->GetMethodID(activity_class, "getClassLoader", "()Ljava/lang/ClassLoader;");
}

GodotJavaWrapper::~GodotJavaWrapper() {
	// nothing to do here for now
}

jobject GodotJavaWrapper::get_activity() {
	return activity;
}

jobject GodotJavaWrapper::get_member_object(const char *p_name, const char *p_class, JNIEnv *p_env) {
	if (godot_class) {
		if (p_env == nullptr) {
			p_env = get_jni_env();
		}
		ERR_FAIL_NULL_V(p_env, nullptr);
		jfieldID fid = p_env->GetStaticFieldID(godot_class, p_name, p_class);
		return p_env->GetStaticObjectField(godot_class, fid);
	} else {
		return nullptr;
	}
}

jobject GodotJavaWrapper::get_class_loader() {
	if (_get_class_loader) {
		JNIEnv *env = get_jni_env();
		ERR_FAIL_NULL_V(env, nullptr);
		return env->CallObjectMethod(activity, _get_class_loader);
	} else {
		return nullptr;
	}
}

GodotJavaViewWrapper *GodotJavaWrapper::get_godot_view() {
	if (_godot_view != nullptr) {
		return _godot_view;
	}
	JNIEnv *env = get_jni_env();
	ERR_FAIL_NULL_V(env, nullptr);
	jmethodID godot_view_getter = env->GetMethodID(godot_class, "getRenderView", "()Lorg/godotengine/godot/GodotRenderView;");
	_godot_view = new GodotJavaViewWrapper(env->CallObjectMethod(godot_instance, godot_view_getter));
	return _godot_view;
}

bool GodotJavaWrapper::on_video_init(JNIEnv *p_env) {
	if (_on_video_init) {
		if (p_env == nullptr) {
			p_env = get_jni_env();
		}
		ERR_FAIL_NULL_V(p_env, false);
		return p_env->CallBooleanMethod(godot_instance, _on_video_init);
	}
	return false;
}

void GodotJavaWrapper::on_godot_setup_completed(JNIEnv *p_env) {
	if (_on_godot_setup_completed) {
		if (p_env == nullptr) {
			p_env = get_jni_env();
		}
		p_env->CallVoidMethod(godot_instance, _on_godot_setup_completed);
	}
}

void GodotJavaWrapper::on_godot_main_loop_started(JNIEnv *p_env) {
	if (_on_godot_main_loop_started) {
		if (p_env == nullptr) {
			p_env = get_jni_env();
		}
		ERR_FAIL_NULL(p_env);
		p_env->CallVoidMethod(godot_instance, _on_godot_main_loop_started);
	}
}

void GodotJavaWrapper::restart(JNIEnv *p_env) {
	if (_restart) {
		if (p_env == nullptr) {
			p_env = get_jni_env();
		}
		ERR_FAIL_NULL(p_env);
		p_env->CallVoidMethod(godot_instance, _restart);
	}
}

void GodotJavaWrapper::force_quit(JNIEnv *p_env) {
	if (_finish) {
		if (p_env == nullptr) {
			p_env = get_jni_env();
		}
		ERR_FAIL_NULL(p_env);
		p_env->CallVoidMethod(godot_instance, _finish);
	}
}

void GodotJavaWrapper::set_keep_screen_on(bool p_enabled) {
	if (_set_keep_screen_on) {
		JNIEnv *env = get_jni_env();
		ERR_FAIL_NULL(env);
		env->CallVoidMethod(godot_instance, _set_keep_screen_on, p_enabled);
	}
}

void GodotJavaWrapper::alert(const String &p_message, const String &p_title) {
	if (_alert) {
		JNIEnv *env = get_jni_env();
		ERR_FAIL_NULL(env);
		jstring jStrMessage = env->NewStringUTF(p_message.utf8().get_data());
		jstring jStrTitle = env->NewStringUTF(p_title.utf8().get_data());
		env->CallVoidMethod(godot_instance, _alert, jStrMessage, jStrTitle);
	}
}

int GodotJavaWrapper::get_gles_version_code() {
	JNIEnv *env = get_jni_env();
	ERR_FAIL_NULL_V(env, 0);
	if (_get_GLES_version_code) {
		return env->CallIntMethod(godot_instance, _get_GLES_version_code);
	}
	return 0;
}

bool GodotJavaWrapper::has_get_clipboard() {
	return _get_clipboard != nullptr;
}

String GodotJavaWrapper::get_clipboard() {
	if (_get_clipboard) {
		JNIEnv *env = get_jni_env();
		ERR_FAIL_NULL_V(env, String());
		jstring s = (jstring)env->CallObjectMethod(godot_instance, _get_clipboard);
		return jstring_to_string(s, env);
	} else {
		return String();
	}
}

String GodotJavaWrapper::get_input_fallback_mapping() {
	if (_get_input_fallback_mapping) {
		JNIEnv *env = get_jni_env();
		ERR_FAIL_NULL_V(env, String());
		jstring fallback_mapping = (jstring)env->CallObjectMethod(godot_instance, _get_input_fallback_mapping);
		return jstring_to_string(fallback_mapping, env);
	} else {
		return String();
	}
}

bool GodotJavaWrapper::has_set_clipboard() {
	return _set_clipboard != nullptr;
}

void GodotJavaWrapper::set_clipboard(const String &p_text) {
	if (_set_clipboard) {
		JNIEnv *env = get_jni_env();
		ERR_FAIL_NULL(env);
		jstring jStr = env->NewStringUTF(p_text.utf8().get_data());
		env->CallVoidMethod(godot_instance, _set_clipboard, jStr);
	}
}

bool GodotJavaWrapper::has_has_clipboard() {
	return _has_clipboard != nullptr;
}

bool GodotJavaWrapper::has_clipboard() {
	if (_has_clipboard) {
		JNIEnv *env = get_jni_env();
		ERR_FAIL_NULL_V(env, false);
		return env->CallBooleanMethod(godot_instance, _has_clipboard);
	} else {
		return false;
	}
}

bool GodotJavaWrapper::request_permission(const String &p_name) {
	if (_request_permission) {
		JNIEnv *env = get_jni_env();
		ERR_FAIL_NULL_V(env, false);
		jstring jStrName = env->NewStringUTF(p_name.utf8().get_data());
		return env->CallBooleanMethod(godot_instance, _request_permission, jStrName);
	} else {
		return false;
	}
}

bool GodotJavaWrapper::request_permissions() {
	if (_request_permissions) {
		JNIEnv *env = get_jni_env();
		ERR_FAIL_NULL_V(env, false);
		return env->CallBooleanMethod(godot_instance, _request_permissions);
	} else {
		return false;
	}
}

Vector<String> GodotJavaWrapper::get_granted_permissions() const {
	Vector<String> permissions_list;
	if (_get_granted_permissions) {
		JNIEnv *env = get_jni_env();
		ERR_FAIL_NULL_V(env, permissions_list);
		jobject permissions_object = env->CallObjectMethod(godot_instance, _get_granted_permissions);
		jobjectArray *arr = reinterpret_cast<jobjectArray *>(&permissions_object);

		jsize len = env->GetArrayLength(*arr);
		for (int i = 0; i < len; i++) {
			jstring jstr = (jstring)env->GetObjectArrayElement(*arr, i);
			String str = jstring_to_string(jstr, env);
			permissions_list.push_back(str);
			env->DeleteLocalRef(jstr);
		}
	}
	return permissions_list;
}

void GodotJavaWrapper::init_input_devices() {
	if (_init_input_devices) {
		JNIEnv *env = get_jni_env();
		ERR_FAIL_NULL(env);
		env->CallVoidMethod(godot_instance, _init_input_devices);
	}
}

jobject GodotJavaWrapper::get_surface() {
	if (_get_surface) {
		JNIEnv *env = get_jni_env();
		ERR_FAIL_NULL_V(env, nullptr);
		return env->CallObjectMethod(godot_instance, _get_surface);
	} else {
		return nullptr;
	}
}

bool GodotJavaWrapper::is_activity_resumed() {
	if (_is_activity_resumed) {
		JNIEnv *env = get_jni_env();
		ERR_FAIL_NULL_V(env, false);
		return env->CallBooleanMethod(godot_instance, _is_activity_resumed);
	} else {
		return false;
	}
}

void GodotJavaWrapper::vibrate(int p_duration_ms) {
	if (_vibrate) {
		JNIEnv *env = get_jni_env();
		ERR_FAIL_NULL(env);
		env->CallVoidMethod(godot_instance, _vibrate, p_duration_ms);
	}
}

void GodotJavaWrapper::create_new_godot_instance(List<String> args) {
	if (_create_new_godot_instance) {
		JNIEnv *env = get_jni_env();
		ERR_FAIL_NULL(env);
		jobjectArray jargs = env->NewObjectArray(args.size(), env->FindClass("java/lang/String"), env->NewStringUTF(""));
		for (int i = 0; i < args.size(); i++) {
			env->SetObjectArrayElement(jargs, i, env->NewStringUTF(args[i].utf8().get_data()));
		}
		env->CallVoidMethod(godot_instance, _create_new_godot_instance, jargs);
	}
}
