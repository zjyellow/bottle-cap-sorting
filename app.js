const videos = [...document.querySelectorAll('video')];

videos.forEach((video) => {
  video.addEventListener('play', () => {
    videos.forEach((other) => {
      if (other !== video) other.pause();
    });
  });
});

document.querySelectorAll('details').forEach((details) => {
  details.addEventListener('toggle', () => {
    if (!details.open) {
      details.querySelectorAll('video').forEach((video) => video.pause());
    }
  });
});
