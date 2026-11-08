export const RenderStatistics = {
  mounted() {
    // Handle server ping
    this.handleEvent("renderstats:ping", ({ ping_id }) => {
      // Send pong to LiveView
      this.pushEvent("renderstats:pong", { ping_id });
    });

    // Handle server request for JS render metric
    this.handleEvent("renderstats:js", ({ }) => {
      calculateAverageFrameTime().then((average) => {
        // Send render time to LiveView
        this.pushEvent("renderstats:js", { time: Math.round(average) });
      });
    });
  }
};


// Functions to calculate average frame time
function measureAnimationFrame() {
  return new Promise((resolve) => {
    const start = performance.now();
    requestAnimationFrame(() => {
      const end = performance.now();
      resolve(end - start);
    });
  });
}

function calculateAverageFrameTime() {
  const measurements = [];
  const interval = 250;
  const count = 4;

  return new Promise((resolve) => {
    let i = 0;
    function measure() {
      measureAnimationFrame().then((time) => {
        measurements.push(time);
        i++;
        if (i < count) {
          setTimeout(measure, interval);
        } else {
          const average = measurements.reduce((sum, time) => sum + time, 0) / count;
          resolve(average);
        }
      });
    }
    measure();
  });
}