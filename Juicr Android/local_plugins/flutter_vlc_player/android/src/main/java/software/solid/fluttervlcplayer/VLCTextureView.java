package software.solid.fluttervlcplayer;

import android.content.Context;
import android.graphics.Color;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.SurfaceView;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import org.videolan.libvlc.MediaPlayer;
import org.videolan.libvlc.interfaces.IVLCVout;

public class VLCTextureView extends FrameLayout implements View.OnLayoutChangeListener, IVLCVout.OnNewVideoLayoutListener {

    private MediaPlayer mMediaPlayer = null;
    protected Context mContext;

    private final SurfaceView videoSurfaceView;
    private final SurfaceView subtitleSurfaceView;
    private final Handler mHandler;
    private Runnable mLayoutChangeRunnable = null;
    private int videoWidth = 0;
    private int videoHeight = 0;

    public VLCTextureView(final Context context) {
        super(context);
        mContext = context;
        mHandler = new Handler(Looper.getMainLooper());

        setFocusable(false);
        setBackgroundColor(Color.BLACK);

        videoSurfaceView = new SurfaceView(context);
        videoSurfaceView.setBackgroundColor(Color.BLACK);
        videoSurfaceView.setZOrderOnTop(false);

        subtitleSurfaceView = new SurfaceView(context);
        subtitleSurfaceView.setZOrderMediaOverlay(true);
        subtitleSurfaceView.getHolder().setFormat(android.graphics.PixelFormat.TRANSLUCENT);

        final FrameLayout.LayoutParams matchParent = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
        );
        addView(videoSurfaceView, matchParent);
        addView(subtitleSurfaceView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
        ));
        addOnLayoutChangeListener(this);
    }

    public void dispose() {
        removeOnLayoutChangeListener(this);

        if (mLayoutChangeRunnable != null) {
            mHandler.removeCallbacks(mLayoutChangeRunnable);
            mLayoutChangeRunnable = null;
        }

        if (mMediaPlayer != null) {
            mMediaPlayer.getVLCVout().detachViews();
        }
        mMediaPlayer = null;
        mContext = null;
    }

    public void setMediaPlayer(MediaPlayer mediaPlayer) {
        if (mediaPlayer == null && mMediaPlayer != null) {
            mMediaPlayer.getVLCVout().detachViews();
        }

        mMediaPlayer = mediaPlayer;

        if (mMediaPlayer != null) {
            attachVlcViews();
        }
    }

    private void attachVlcViews() {
        if (mMediaPlayer == null) {
            return;
        }
        final int width = getWidth();
        final int height = getHeight();
        if (width > 1 && height > 1) {
            mMediaPlayer.getVLCVout().setWindowSize(width, height);
        }
        if (!mMediaPlayer.getVLCVout().areViewsAttached()) {
            mMediaPlayer.getVLCVout().setVideoView(videoSurfaceView);
            mMediaPlayer.getVLCVout().setSubtitlesView(subtitleSurfaceView);
            mMediaPlayer.getVLCVout().attachViews(this);
        }
        mMediaPlayer.setVideoTrackEnabled(true);
    }

    @Override
    public void onNewVideoLayout(IVLCVout vlcVout, int width, int height, int visibleWidth, int visibleHeight, int sarNum, int sarDen) {
        if (width * height == 0) return;

        videoWidth = visibleWidth > 0 ? visibleWidth : width;
        videoHeight = visibleHeight > 0 ? visibleHeight : height;
        setSize(videoWidth, videoHeight);
    }

    @Override
    public void onLayoutChange(View view, int left, int top, int right, int bottom, int oldLeft, int oldTop, int oldRight, int oldBottom) {
        if (left != oldLeft || top != oldTop || right != oldRight || bottom != oldBottom) {
            updateLayoutSize(view);
        }
    }

    public void updateLayoutSize(View view) {
        if (mMediaPlayer != null) {
            final int width = view.getWidth();
            final int height = view.getHeight();
            if (width <= 1 || height <= 1) {
                return;
            }
            mMediaPlayer.getVLCVout().setWindowSize(width, height);
            mMediaPlayer.updateVideoSurfaces();
            if (videoWidth > 0 && videoHeight > 0) {
                setSize(videoWidth, videoHeight);
            }
        }
    }

    private void setSize(int width, int height) {
        if (width * height <= 1) return;

        int w = this.getWidth();
        int h = this.getHeight();
        if (w <= 1 || h <= 1) return;

        float videoAR = (float) width / (float) height;
        float screenAR = (float) w / (float) h;

        if (screenAR < videoAR) {
            h = (int) (w / videoAR);
        } else {
            w = (int) (h * videoAR);
        }

        applySurfaceSize(w, h);
        this.invalidate();
    }

    private void applySurfaceSize(int width, int height) {
        final FrameLayout.LayoutParams videoParams = new FrameLayout.LayoutParams(
                width,
                height,
                Gravity.CENTER
        );
        videoSurfaceView.setLayoutParams(videoParams);

        final FrameLayout.LayoutParams subtitleParams = new FrameLayout.LayoutParams(
                width,
                height,
                Gravity.CENTER
        );
        subtitleSurfaceView.setLayoutParams(subtitleParams);
    }

}
