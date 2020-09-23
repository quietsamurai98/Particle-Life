def tick args
  args.state.universe ||= big_bang_2(args)
  args.state.universe = big_bang_2(args) if args.inputs.keyboard.key_down.space
  universe            = args.state.universe
  repopulate(universe, args) if args.inputs.keyboard.key_down.enter
  cam_x               = 1280 / 2
  cam_y               = 720 / 2
  cam_zoom            = 1
  universe.zoom(cam_x, cam_y, cam_zoom)
  universe.step
  args.outputs.labels << {x: 10, y: 30, text: "FPS: #{$gtk.current_framerate.to_s.to_i}", r: 255, g: 0, b: 0}
  args.outputs.background_color = [0,0,0]
end

def big_bang_2(args)
  universe = Universe.new(9, 100, 1280, 720)
  universe.reseed(-0.02, 0.06, 0.0, 20.0, 20.0, 70.0, 0.025, false)
  universe = Universe.new(6, 100, 1280, 720)
  universe.reseed(0.02, 0.04, 0.0, 30.0, 30.0, 100.0, 0.01, false)
  universe = Universe.new(6, 100, 1280, 720)
  universe.reseed(0.0, 0.06, 0.0, 20.0, 10.0, 50.0, 0.1, true)
  universe = Universe.new(7, 100, 1280, 720)
  universe.reseed(-0.02, 0.1, 10.0, 20.0, 20.0, 60.0, 0.1, false)
  args.outputs.static_sprites.clear
  args.outputs.static_sprites << universe.draw(1.0)
  universe.step
  universe
end

def repopulate(universe, args)
  universe.set_random_particles
  args.outputs.static_sprites.clear
  args.outputs.static_sprites << universe.draw(1.0)
  universe.step
end

RADIUS   = 5.0
DIAMETER = 2.0 * RADIUS
R_SMOOTH = 2.0


class Universe

  attr_accessor :m_particles, :m_types, :m_rand_gen, :m_center_x, :m_center_y, :m_zoom, :m_attract_mean, :m_attract_std, :m_minr_lower, :m_minr_upper, :m_maxr_lower, :m_maxr_upper, :m_friction, :m_flat_force, :m_wrap, :m_width, :m_height

  def initialize(num_types, num_particles, width, height)
    #declare ivars

    @m_particles = []
    @m_types     = ParticleTypes.new

    #Initialize everything
    @m_rand_gen = Random.new
    set_population(num_types, num_particles)
    set_size(width, height)
    @m_center_x     = @m_width * 0.5
    @m_center_y     = @m_height * 0.5
    @m_zoom         = 1.0
    @m_attract_mean = 0.0
    @m_attract_std  = 0.0
    @m_minr_lower   = 0.0
    @m_minr_upper   = 0.0
    @m_maxr_lower   = 0.0
    @m_maxr_upper   = 0.0
    @m_friction     = 0.0
    @m_flat_force   = false
    @m_wrap         = true
  end

  def reseed(attract_mean, attract_std, minr_lower, minr_upper, maxr_lower, maxr_upper, friction, flat_force)
    @m_attract_mean = attract_mean
    @m_attract_std  = attract_std
    @m_minr_lower   = minr_lower
    @m_minr_upper   = minr_upper
    @m_maxr_lower   = maxr_lower
    @m_maxr_upper   = maxr_upper
    @m_friction     = friction
    @m_flat_force   = flat_force
    set_random_types
    set_random_particles
  end

  def set_population(num_types, num_particles)
    @m_types.resize(num_types)
    @m_particles = (1..num_particles).map { Particle.new }
  end

  def set_size(width, height)
    @m_width  = width
    @m_height = height
  end

  def set_random_types
    rand_attr = RandomGaussian.new(@m_attract_mean, @m_attract_std)
    rand_minr = RandomUniformReal.new(@m_minr_lower, @m_minr_upper)
    rand_maxr = RandomUniformReal.new(@m_maxr_lower, @m_maxr_upper)
    (0...@m_types.size).each do |i|
      @m_types.m_col[i] = {r: rand(255).greater(1), g: rand(255).greater(1), b: rand(255).greater(1)}
      (0...@m_types.size).each do |j|
        ij = i * @m_types.size + j
        ji = j * @m_types.size + i
        if i == j
          @m_types.m_attract[ij] = -rand_attr.rand(@m_rand_gen).abs
          @m_types.m_min_r[ij]   = DIAMETER
        else
          @m_types.m_attract[ij] = rand_attr.rand(@m_rand_gen)
          @m_types.m_min_r[ij]   = rand_minr.rand(@m_rand_gen).greater(DIAMETER)
        end
        @m_types.m_max_r[ij] = rand_maxr.rand(@m_rand_gen).greater(@m_types.m_min_r[ij])
        @m_types.m_min_r[ji] = @m_types.m_min_r[ij]
        @m_types.m_max_r[ji] = @m_types.m_max_r[ij]
      end
    end
  end

  def set_random_particles
    rand_type = RandomUniformInt.new(0, @m_types.size - 1)
    rand_uni  = RandomUniformReal.new(0.0, 1.0)
    rand_norm = RandomGaussian.new(0.0, 1.0)
    @m_particles.each do |p|
      p.type = rand_type.rand(@m_rand_gen)
      p.x    = (rand_uni.rand(@m_rand_gen) * 0.5 + 0.25) * @m_width
      p.y    = (rand_uni.rand(@m_rand_gen) * 0.5 + 0.25) * @m_height
      p.vx   = rand_norm.rand(@m_rand_gen) * 0.2
      p.vy   = rand_norm.rand(@m_rand_gen) * 0.2
    end
  end

  def toggle_wrap
    @m_wrap = !@m_wrap
  end

  def step
    @m_particles.each do |p|
      @m_particles.each do |q|
        if p == q
          next
        end
        dx = q.x - p.x
        dy = q.y - p.y
        if @m_wrap
          if dx > @m_width * 0.5
            dx -= @m_width
          elsif dx < -@m_width * 0.5
            dx += @m_width
          end
          if dy > @m_height * 0.5
            dy -= @m_height
          elsif dy < -@m_height * 0.5
            dy += @m_height
          end
        end
        r2    = dx * dx + dy * dy
        pq_ti = p.type * @m_types.size + q.type
        min_r = @m_types.m_min_r[pq_ti]
        max_r = @m_types.m_max_r[pq_ti]
        if r2 > max_r * max_r || r2 < 0.01
          next
        end
        r  = Math.sqrt(r2)
        dx /= r
        dy /= r
        f  = 0.0
        if r > min_r
          if @m_flat_force
            f = @m_types.m_attract[pq_ti]
          else
            numer = 2.0 * (r - 0.5 * (max_r + min_r)).abs
            denom = max_r - min_r
            f     = @m_types.m_attract[pq_ti] * (1.0 - numer / denom)
          end
        else
          f = R_SMOOTH * min_r * (1.0 / (min_r + R_SMOOTH) - 1.0 / (r + R_SMOOTH));
        end
        p.vx += f * dx
        p.vy += f * dy
      end
    end

    @m_particles.each do |p|
      # Update position and velocity
      p.x  += p.vx
      p.y  += p.vy
      p.vx *= (1.0 - @m_friction)
      p.vy *= (1.0 - @m_friction)
      if @m_wrap
        if p.x < 0
          p.x += @m_width
        elsif p.x >= @m_width
          p.x -= @m_width
        end
        if p.y < 0
          p.y += @m_height
        elsif p.y >= @m_height
          p.y -= @m_height
        end
      else
        if p.x <= DIAMETER
          p.vx = -p.vx
          p.x  = DIAMETER
        elsif p.x >= @m_width - DIAMETER
          p.vx = -p.vx
          p.x  = @m_width - DIAMETER
        end
        if p.y <= DIAMETER
          p.vy = -p.vy
          p.y  = DIAMETER
        elsif p.y >= @m_height - DIAMETER
          p.vy = -p.vy
          p.y  = @m_height - DIAMETER
        end
      end
      x     = (p.x - @m_center_x) * @m_zoom + (@m_width / 2.0)
      y     = (p.y - @m_center_y) * @m_zoom + (@m_height / 2.0)
      p.sprite.x    = x - RADIUS
      p.sprite.y    = y - RADIUS
      p.sprite.w    = RADIUS * 2
      p.sprite.h    = RADIUS * 2
    end
  end

  def draw(opacity)
    @m_particles.map do |p|
      x     = (p.x - @m_center_x) * @m_zoom + (@m_width / 2.0)
      y     = (p.y - @m_center_y) * @m_zoom + (@m_height / 2.0)
      color = @m_types.m_col[p.type]
      p.sprite.x    = x - RADIUS
      p.sprite.y    = y - RADIUS
      p.sprite.w    = RADIUS * 2
      p.sprite.h    = RADIUS * 2
      p.sprite.r    = color[:r]
      p.sprite.g    = color[:g]
      p.sprite.b    = color[:b]
      p.sprite.a    = (opacity * 255.0).clamp(1, 255)
      p.sprite
    end
  end

  def zoom(cx, cy, zoom)
    @m_zoom     = zoom.greater(1.0)
    @m_center_x = cx.clamp(@m_width * (1.0 - 0.5 / @m_zoom), @m_width * (0.5 / @m_zoom))
    @m_center_y = cy.clamp(@m_height * (1.0 - 0.5 / @m_zoom), @m_height * (0.5 / @m_zoom))
  end

  def get_index(x, y)
    cx, cy = *to_center(x, y)
    (0..@m_particles.length - 1).each do |i|
      dx = @m_particles[i].x - cx
      dy = @m_particles[i].y - cy
      if dx * dx + dy * dy < RADIUS * RADIUS
        return i
      end
    end
    -1
  end

  def get_particle_x(index)
    @m_particles[index].x
  end

  def get_particle_y(index)
    @m_particles[index].y
  end

  def to_center(x, y)
    [
        @m_center_x + (x - @m_width / 2) / @m_zoom,
        @m_center_y + (y - @m_height / 2) / @m_zoom,
    ]
  end

  def print_params

  end
end

class Particle
  attr_accessor :x, :y, :vx, :vy, :type, :sprite

  def initialize(params = {})
    @x      = params[:x] || 0.0
    @y      = params[:x] || 0.0
    @vx     = params[:vx] || 0.0
    @vy     = params[:vy] || 0.0
    @type   = params[:type] || 0
    @sprite = Sprite.new({
                             x:    @x - RADIUS,
                             y:    @y - RADIUS,
                             w:    RADIUS * 2,
                             h:    RADIUS * 2,
                             path: 'sprites/circle-white.png',
                             r:    255,
                             g:    255,
                             b:    255,
                             a:    255
                         })
  end

  def to_hash
    {
        x:    @x,
        y:    @y,
        vx:   @vx,
        vy:   @vy,
        type: @type
    }
  end
end

class ParticleTypes
  attr_accessor :m_col, :m_attract, :m_min_r, :m_max_r, :size

  def initialize
    @m_col     = []
    @m_attract = []
    @m_min_r   = []
    @m_max_r   = []
    @size      = 0
  end

  def resize(size)
    @m_col     = (1..size).map { {r: 255, g: 255, b: 255} }
    @m_attract = (1..size * size).map { 0.0 }
    @m_min_r   = (1..size * size).map { 0.0 }
    @m_max_r   = (1..size * size).map { 0.0 }
    @size      = size
  end
end

class RandomGaussian
  def initialize(mean = 0.0, sd = 1.0)
    @mean, @sd         = mean, sd
    @compute_next_pair = false
  end

  def rand(rng = Kernel)
    if (@compute_next_pair = !@compute_next_pair)
      # Compute a pair of random values with normal distribution.
      # See http://en.wikipedia.org/wiki/Box-Muller_transform
      theta = 2 * Math::PI * rng.rand
      scale = @sd * Math.sqrt(-2 * Math.log(1 - rng.rand))
      #scale = @sd * Math.sqrt(-2 * Math.log(1 - Kernel.rand))
      @g1 = @mean + scale * Math.sin(theta)
      @g0 = @mean + scale * Math.cos(theta)
    else
      @g1
    end
  end
end

class RandomUniformReal
  def initialize(min = 0.0, max = 1.0)
    @scale, @shift = max - min, min
  end

  def rand(rng = Kernel)
    rng.rand * @scale.to_f + @shift
    #Kernel.rand() * @scale + @shift
  end
end

class RandomUniformInt
  def initialize(min = 0, max = 1)
    @min = min
    @max = max - min + 1
  end

  def rand(rng = Kernel)
    #rng.rand(@max.to_i) + @min
    #(Kernel.rand * @max + @min).to_int
    (rng.rand * @max + @min).to_int
  end
end

class Sprite
  attr_sprite

  attr_accessor :x, :y, :w, :h, :path, :angle, :a, :r, :g, :b, :tile_x,
                :tile_y, :tile_w, :tile_h, :flip_horizontally,
                :flip_vertically, :angle_anchor_x, :angle_anchor_y, :id,
                :source_x, :source_y, :source_w, :source_h

  def initialize(params = {})
    @x    = params[:x] || -1
    @y    = params[:y] || -1
    @w    = params[:w] || 1
    @h    = params[:h] || 1
    @r    = params[:r] || 255
    @g    = params[:g] || 255
    @b    = params[:b] || 255
    @a    = params[:a] || 255
    @path = params[:sprite] || 'sprites/circle-white.png'
  end

  def primitive_marker
    :sprite
  end

  def sprite
    self
  end

  def x1
    @x
  end

  def x1= value
    @x = value
  end

  def y1
    @y
  end

  def y1= value
    @y = value
  end
end